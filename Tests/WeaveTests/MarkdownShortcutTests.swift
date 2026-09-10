import Foundation
import Testing
@testable import Weave

struct MarkdownShortcutTests {
    private func type(_ character: String, after text: String, marked: Bool = false) -> MarkdownShortcut.Edit? {
        MarkdownShortcut.match(text: text, range: NSRange(location: text.utf16.count, length: 0), replacement: character, hasMarkedText: marked)
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
        #expect(type(" ", after: ">")?.style == .quote)
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
        for text in ["**bold", "***", "\\*literal", "*literal\\", "word*part", "中文*部分", "* leading", "*trailing ", "*first\nsecond", "`code *literal", "**bold*more"] {
            #expect(type("*", after: text) == nil, "Unexpected conversion: \(text)")
        }
        #expect(type("`", after: "``code") == nil)
        #expect(type("`", after: "\\`code") == nil)
        #expect(type("*", after: "(**bold*")?.style == .bold)
    }

    @Test func boldCanTouchSurroundingText() {
        #expect(type("*", after: "正文**加粗*") == .init(range: NSRange(location: 2, length: 5), replacement: "加粗", style: .bold))
        #expect(MarkdownShortcut.match(text: "正文**加粗*后文", range: NSRange(location: 7, length: 0), replacement: "*", hasMarkedText: false)?.style == .bold)
        #expect(type("*", after: "text**bold*")?.style == .bold)
        #expect(type("*", after: "正文\\**加粗*") == nil)
        #expect(type("*", after: "正文`**加粗*") == nil)
    }

    @Test func continuesAndExitsListsAndQuotes() {
        #expect(type("\n", after: "• 中文😀") == .init(range: NSRange(location: 6, length: 0), replacement: "\n• ", style: .bullet))
        #expect(type("\n", after: "│ 引用")?.replacement == "\n│ ")
        #expect(type("\n", after: "第一行\n• ") == .init(range: NSRange(location: 4, length: 2), replacement: "", style: .body))
        #expect(type("\n", after: "│ ")?.style == .body)
        #expect(type("\n", after: "普通文本") == nil)
    }

    @Test func ignoresCompositionPasteSelectionAndInvalidOffsets() {
        #expect(type(" ", after: "#", marked: true) == nil)
        #expect(type("**", after: "**bold") == nil)
        #expect(MarkdownShortcut.match(text: "#", range: NSRange(location: 0, length: 1), replacement: " ", hasMarkedText: false) == nil)
        #expect(MarkdownShortcut.match(text: "😀", range: NSRange(location: 1, length: 0), replacement: "*", hasMarkedText: false) == nil)
        #expect(MarkdownShortcut.match(text: "*wordrest", range: NSRange(location: 5, length: 0), replacement: "*", hasMarkedText: false) == nil)
    }
}
