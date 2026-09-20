import Foundation
import Testing

@testable import Weave

struct MarkdownShortcutTests {
    private func type(_ character: String, after text: String, marked: Bool = false) -> MarkdownShortcut.Edit? {
        MarkdownShortcut.match(
            text: text, range: NSRange(location: text.utf16.count, length: 0), replacement: character, hasMarkedText: marked)
    }

    @Test func inlineCodeCanTouchTextOnBothSides() {
        for prefix in ["\u{624B}\u{518C}", "word", "123", "\u{1F600}"] {
            let text = prefix + "`value" + "suffix"
            let range = NSRange(location: prefix.utf16.count + 6, length: 0)
            let edit = MarkdownShortcut.match(text: text, range: range, replacement: "`", hasMarkedText: false)
            #expect(edit == .init(range: NSRange(location: prefix.utf16.count, length: 6), replacement: "value", style: .code))
            #expect(MarkdownShortcut.match(text: text, range: range, replacement: "`", hasMarkedText: true) == nil)
        }
    }

    @Test func inlineShortcutsCanTouchSurroundingText() {
        let formats: [(String, MarkdownShortcut.Style)] = [("**", .bold), ("*", .italic), ("~~", .strike), ("`", .code)]
        for (marker, style) in formats {
            for prefix in ["", "正文", "word", "123", "_", "😀"] {
                for suffix in ["", "后文", "word", "123", "_"] {
                    let before = prefix + marker + "内容😀" + marker.dropLast()
                    let range = NSRange(location: before.utf16.count, length: 0)
                    let edit = MarkdownShortcut.match(
                        text: before + suffix, range: range, replacement: String(marker.last!), hasMarkedText: false)
                    #expect(
                        edit
                            == .init(
                                range: NSRange(location: prefix.utf16.count, length: before.utf16.count - prefix.utf16.count),
                                replacement: "内容😀", style: style))
                    #expect(
                        MarkdownShortcut.match(text: before + suffix, range: range, replacement: String(marker.last!), hasMarkedText: true)
                            == nil)
                }
            }
        }
    }

    @Test func adjacentDifferentDelimitersDoNotBlockClosure() {
        let formats: [(String, MarkdownShortcut.Style)] = [("**", .bold), ("*", .italic), ("~~", .strike), ("`", .code)]
        for (marker, style) in formats {
            for (nextMarker, _) in formats where marker.last != nextMarker.first {
                let before = marker + "文字" + marker.dropLast()
                let suffix = nextMarker + "后文" + nextMarker
                let edit = MarkdownShortcut.match(
                    text: before + suffix, range: NSRange(location: before.utf16.count, length: 0), replacement: String(marker.last!),
                    hasMarkedText: false)
                #expect(edit == .init(range: NSRange(location: 0, length: before.utf16.count), replacement: "文字", style: style))
            }
        }
    }

    @Test func doesNotSplitAnExistingDelimiterRun() {
        for marker in ["*", "**", "~~", "`"] {
            let before = marker + "value" + marker.dropLast()
            #expect(
                MarkdownShortcut.match(
                    text: before + marker, range: NSRange(location: before.utf16.count, length: 0), replacement: String(marker.last!),
                    hasMarkedText: false) == nil)
        }
    }

    @Test func strikeClosureRespectsEscapesCodeAndComposition() {
        #expect(type("~", after: "~~done~")?.style == .strike)
        #expect(type("~", after: "\\~~done~") == nil)
        #expect(type("~", after: "`~~done~") == nil)
        #expect(type("~", after: "~~done~", marked: true) == nil)
        #expect(type("~", after: "~~ done~") == nil)
    }

    @Test func convertsParagraphPrefixes() {
        for level in 1...6 {
            let marker = String(repeating: "#", count: level)
            #expect(type(" ", after: marker) == .init(range: NSRange(location: 0, length: level), replacement: "", style: .heading(level)))
        }
        for marker in ["-", "*", "+"] {
            #expect(type(" ", after: marker)?.replacement == "• ")
            #expect(type(" ", after: marker)?.style == .bullet)
        }
        #expect(type(" ", after: ">") == .init(range: NSRange(location: 0, length: 1), replacement: "", style: .quote))
        for text in ["#######", "text #", " #", "--", "## title"] {
            #expect(type(" ", after: text) == nil)
        }
    }

    @Test func formatsInlineClosuresAndUsesUTF16Offsets() {
        #expect(type("*", after: "😀 中文 **粗体*") == .init(range: NSRange(location: 6, length: 5), replacement: "粗体", style: .bold))
        #expect(type("*", after: "*斜体")?.style == .italic)
        #expect(type("`", after: "`let x = 1")?.replacement == "let x = 1")
        #expect(type("*", after: "中文\n**😀*") == .init(range: NSRange(location: 3, length: 5), replacement: "😀", style: .bold))
    }

    @Test func leavesLiteralAndUnfinishedSyntaxAlone() {
        for text in [
            "**bold", "***", "\\*literal", "*literal\\", "* leading", "*trailing ", "*first\nsecond", "`code *literal", "**bold*more",
        ] {
            #expect(type("*", after: text) == nil, "Unexpected conversion: \(text)")
        }
        #expect(type("`", after: "``code") == nil)
        #expect(type("`", after: "\\`code") == nil)
        #expect(type("*", after: "(**bold*")?.style == .bold)
    }

    @Test func boldCanTouchSurroundingText() {
        #expect(type("*", after: "正文**加粗*") == .init(range: NSRange(location: 2, length: 5), replacement: "加粗", style: .bold))
        #expect(
            MarkdownShortcut.match(text: "正文**加粗*后文", range: NSRange(location: 7, length: 0), replacement: "*", hasMarkedText: false)?.style
                == .bold)
        #expect(type("*", after: "text**bold*")?.style == .bold)
        #expect(type("*", after: "正文\\**加粗*") == nil)
        #expect(type("*", after: "正文`**加粗*") == nil)
    }

    @Test func continuesAndExitsListsAndQuotes() {
        #expect(type("\n", after: "• 中文😀") == .init(range: NSRange(location: 6, length: 0), replacement: "\n• ", style: .bullet))
        #expect(type("\n", after: "第一行\n• ") == .init(range: NSRange(location: 4, length: 2), replacement: "", style: .body))
        #expect(type("\n", after: "普通文本") == nil)
    }

    @Test func ignoresCompositionPasteSelectionAndInvalidOffsets() {
        #expect(type(" ", after: "#", marked: true) == nil)
        #expect(type("**", after: "**bold") == nil)
        #expect(MarkdownShortcut.match(text: "#", range: NSRange(location: 0, length: 1), replacement: " ", hasMarkedText: false) == nil)
        #expect(MarkdownShortcut.match(text: "😀", range: NSRange(location: 1, length: 0), replacement: "*", hasMarkedText: false) == nil)
    }
}
