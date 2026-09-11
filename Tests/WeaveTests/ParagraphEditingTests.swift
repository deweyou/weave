import SwiftUI
import Testing
@testable import Weave

struct ParagraphEditingTests {
    @Test func headingChangesWholeParagraphAndPersistsRole() throws {
        var text = AttributedString("第一段文字\n第二段文字")
        var selection = AttributedTextSelection(range: text.range(of: "一段")!)
        ParagraphEditing.apply("heading:2", to: &text, selection: &selection)
        #expect(text[text.range(of: "第一段文字")!][ParagraphStyleAttribute.self] == "heading:2")
        #expect(text[text.range(of: "第二段文字")!][ParagraphStyleAttribute.self] == nil)
        var note = Note(id: UUID(), text: "", createdAt: Date(), updatedAt: Date())
        note.richText = text
        let decoded = try JSONDecoder().decode(Note.self, from: JSONEncoder().encode(note))
        #expect(decoded.richText[decoded.richText.range(of: "第一段文字")!][ParagraphStyleAttribute.self] == "heading:2")
    }

    @Test func listConversionAndTaskTogglePreserveContent() {
        var text = AttributedString("甲\n乙")
        var selection = AttributedTextSelection(range: text.startIndex..<text.endIndex)
        ParagraphEditing.apply("numbered", to: &text, selection: &selection)
        #expect(String(text.characters) == "1. 甲\n2. 乙")
        ParagraphEditing.apply("task", to: &text, selection: &selection)
        #expect(String(text.characters) == "☐ 甲\n☐ 乙")
        selection = AttributedTextSelection(insertionPoint: text.startIndex)
        ParagraphEditing.toggleTask(in: &text, selection: &selection)
        #expect(String(text.characters) == "☑ 甲\n☐ 乙")
        ParagraphEditing.apply("body", to: &text, selection: &selection)
        #expect(String(text.characters) == "甲\n☐ 乙")
    }

    @Test func inputRulesContinueNumberingTasksAndNestedLists() {
        func match(_ source: String, _ input: String) -> MarkdownShortcut.Edit? {
            MarkdownShortcut.match(text: source, range: NSRange(location: source.utf16.count, length: 0), replacement: input, hasMarkedText: false)
        }
        #expect(match("1.", " ")?.style == .numbered)
        #expect(match("9. 完成", "\n")?.replacement == "\n10. ")
        #expect(match("\t• 子项", "\n")?.replacement == "\n\t• ")
        #expect(match("☑ 已完成", "\n")?.replacement == "\n☐ ")
        #expect(match("☐ ", "\n")?.style == .body)
        #expect(match("• [ ]", " ")?.replacement == "☐ ")
        #expect(match("```swift", "\n")?.style == .codeBlock)
    }
}
