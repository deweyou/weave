import SwiftUI
import Testing

@testable import Weave

struct ParagraphEditingTests {
    @Test @MainActor func headingConversionPreservesInlineEmphasisLinksAndCodeThroughPersistence() throws {
        let source = "Plain **Strong** *Italic* [Link](https://example.com) `code`"
        let context = EnvironmentValues().fontResolutionContext
        for level in 1...6 {
            var text = MarkdownFormatting.render(source)
            var selection = AttributedTextSelection(range: text.startIndex..<text.endIndex)
            ParagraphEditing.apply("heading:\(level)", to: &text, selection: &selection, context: context)
            let exported = MarkdownFormatting.serialize(text, context: context)
            #expect(exported == String(repeating: "#", count: level) + " " + source)
            var note = Note(id: UUID(), text: "", createdAt: Date(), updatedAt: Date())
            note.richText = text
            let decoded = try JSONDecoder().decode(Note.self, from: JSONEncoder().encode(note))
            text = NativeTextAttributes.rich(NativeTextAttributes.native(decoded.richText, context: context))
            #expect(MarkdownFormatting.serialize(text, context: context) == exported)
            selection = AttributedTextSelection(range: text.startIndex..<text.endIndex)
            ParagraphEditing.apply("body", to: &text, selection: &selection, context: context)
            #expect(MarkdownFormatting.serialize(text, context: context) == source)
        }
    }

    @Test @MainActor func togglingInlineBoldDoesNotRemoveHeadingWeight() {
        let context = EnvironmentValues().fontResolutionContext
        var attributes = AttributeContainer()
        attributes[ParagraphStyleAttribute.self] = "heading:2"
        attributes[InlineEmphasisAttribute.self] = 0
        attributes.font = ParagraphEditing.font(for: "heading:2")
        #expect(DocumentTypography.emphasis(in: attributes, context: context) == 0)
        DocumentTypography.setEmphasis(1, enabled: true, in: &attributes, context: context)
        #expect(DocumentTypography.emphasis(in: attributes, context: context) == 1)
        DocumentTypography.setEmphasis(1, enabled: false, in: &attributes, context: context)
        #expect(DocumentTypography.emphasis(in: attributes, context: context) == 0)
        #expect(attributes.font == ParagraphEditing.font(for: "heading:2"))
    }

    @Test @MainActor func legacyMigrationRecognizesSemanticFontsButDoesNotGuessFromSizes() throws {
        var text = AttributedString("Heading\nLarge body")
        text[text.range(of: "Heading")!].font = .title
        text[text.range(of: "Large body")!].font = .system(size: 32)
        var note = Note(id: UUID(), text: "", createdAt: Date(), updatedAt: Date())
        note.richText = text
        let restored = try JSONDecoder().decode(Note.self, from: JSONEncoder().encode(note)).richText
        #expect(restored[restored.range(of: "Heading")!][ParagraphStyleAttribute.self] == "heading:1")
        #expect(restored[restored.range(of: "Large body")!][ParagraphStyleAttribute.self] == nil)
        let native = NativeTextAttributes.native(restored, context: EnvironmentValues().fontResolutionContext)
        let again = NativeTextAttributes.rich(native)
        #expect(again[again.range(of: "Large body")!][ParagraphStyleAttribute.self] == nil)
        var migrated = restored
        ParagraphEditing.migrateLegacyAttributes(&migrated)
        #expect(migrated == restored)
    }

    @Test func legacyTaskMarkersMigrateToSemanticStateWithoutVisibleCharacters() {
        var text = AttributedString("☐ Open\n☑ Done")
        text[ParagraphStyleAttribute.self] = "task"

        ParagraphEditing.migrateLegacyAttributes(&text)

        #expect(String(text.characters) == "Open\nDone")
        #expect(text[text.range(of: "Open")!][TaskStateAttribute.self] == false)
        #expect(text[text.range(of: "Done")!][TaskStateAttribute.self] == true)
        #expect(MarkdownFormatting.serialize(text, context: EnvironmentValues().fontResolutionContext) == "- [ ] Open\n- [x] Done")
    }

    @Test func legacyListsMigrateOnceAndPersistWithoutSelectableMarkers() throws {
        var old = AttributedString("• 中文🌿\n")
        old[ParagraphStyleAttribute.self] = "bullet"
        var numbered = AttributedString("12. 1. 字面内容")
        numbered[ParagraphStyleAttribute.self] = "numbered"
        old += numbered
        var note = Note(id: UUID(), text: "", createdAt: Date(), updatedAt: Date())
        note.richText = old
        let decoded = try JSONDecoder().decode(Note.self, from: JSONEncoder().encode(note))
        #expect(decoded.text == "中文🌿\n1. 字面内容")
        #expect(decoded.richText[decoded.richText.range(of: "中文🌿")!][ListMarkerAttribute.self] == "•")
        #expect(decoded.richText[decoded.richText.range(of: "1. 字面内容")!][ListMarkerAttribute.self] == "12.")
        let restarted = try JSONDecoder().decode(Note.self, from: JSONEncoder().encode(decoded))
        #expect(restarted.richText == decoded.richText)
        var changed = decoded.richText
        var selection = AttributedTextSelection(range: changed.startIndex..<changed.endIndex)
        ParagraphEditing.apply("body", to: &changed, selection: &selection)
        #expect(String(changed.characters) == decoded.text)
        #expect(changed.runs.allSatisfy { $0[ListMarkerAttribute.self] == nil })
    }

    @Test func listMarkerLevelsCycleAndFormatLongSequences() {
        #expect((0..<6).map { ListMarkerFormatting.label(for: "•", depth: $0) } == ["•", "○", "▪", "•", "○", "▪"])
        #expect((0..<6).map { ListMarkerFormatting.label(for: "2.", depth: $0) } == ["2.", "b.", "ii.", "2.", "b.", "ii."])
        #expect(ListMarkerFormatting.label(for: "27.", depth: 1) == "aa.")
        #expect(ListMarkerFormatting.label(for: "49.", depth: 2) == "xlix.")
        #expect(ListMarkerFormatting.label(for: "4000.", depth: 2) == "4000.")
    }

    @Test func childListsRestartPerParentAndSurviveMarkdownRoundTrip() throws {
        let source = "1. Parent A\n    1. Child A\n        1. Detail A\n        1. Detail B\n    1. Child B\n2. Parent B\n    8. Child C"
        let text = MarkdownFormatting.render(source)
        for (label, marker) in [("Child A", "1."), ("Detail A", "1."), ("Detail B", "2."), ("Child B", "2."), ("Child C", "1.")] {
            let range = try #require(text.range(of: label))
            #expect(text[range][ListMarkerAttribute.self] == marker)
        }
        let restored = MarkdownFormatting.render(MarkdownFormatting.serialize(text, context: EnvironmentValues().fontResolutionContext))
        #expect(String(restored.characters) == String(text.characters))
        #expect(restored.runs.compactMap { $0[ListMarkerAttribute.self] } == text.runs.compactMap { $0[ListMarkerAttribute.self] })
    }

    @Test func legacyQuoteMarkerMigratesToComposableQuoteState() {
        var text = AttributedString("│ 引用")
        text[ParagraphStyleAttribute.self] = "quote"

        ParagraphEditing.migrateLegacyAttributes(&text)

        #expect(String(text.characters) == "引用")
        #expect(text[text.startIndex..<text.endIndex][ParagraphStyleAttribute.self] == "body")
        #expect(text[text.startIndex..<text.endIndex][QuoteAttribute.self] == true)
    }

    @Test func emptyParagraphListCommandsPreserveSemanticTypingState() {
        for (style, marker) in [("bullet", "•"), ("numbered", "1."), ("task", "")] {
            var text = AttributedString("Title\n")
            var selection = AttributedTextSelection(insertionPoint: text.endIndex)
            ParagraphEditing.apply(style, to: &text, selection: &selection)
            #expect(String(text.characters) == "Title\n")
            #expect(selection.typingAttributes(in: text)[ListMarkerAttribute.self] == (marker.isEmpty ? nil : marker))
            if case .insertionPoint(let caret) = selection.indices(in: text) {
                #expect(caret == text.endIndex)
            } else {
                Issue.record("Expected insertion point")
            }
        }
    }

    @Test func indentSelectedListsPreservesInlineStyleAndSelection() {
        var text = MarkdownFormatting.render("- First 🌊\n- [ ] Second\nPlain")
        text[text.range(of: "First")!].font = .body.bold()
        let original = text
        var selection = AttributedTextSelection(range: text.startIndex..<text.endIndex)
        ParagraphEditing.indentList(in: &text, selection: &selection, outdent: false)
        #expect(String(text.characters) == "\tFirst 🌊\n\tSecond\nPlain")
        #expect(text[text.range(of: "First")!].font == .body.bold())
        ParagraphEditing.indentList(in: &text, selection: &selection, outdent: true)
        #expect(text == original)
    }

    @Test func indentCaretAndDepthBoundsAreStable() {
        var text = AttributedString("• 🌊")
        var selection = AttributedTextSelection(insertionPoint: text.endIndex)
        for _ in 0..<10 { ParagraphEditing.indentList(in: &text, selection: &selection, outdent: false) }
        #expect(String(text.characters) == String(repeating: "\t", count: 8) + "• 🌊")
        if case .insertionPoint(let caret) = selection.indices(in: text) {
            #expect(caret == text.endIndex)
        } else {
            Issue.record("Expected insertion point")
        }
        for _ in 0..<10 { ParagraphEditing.indentList(in: &text, selection: &selection, outdent: true) }
        #expect(String(text.characters) == "• 🌊")
    }

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
        #expect(String(text.characters) == "甲\n乙")
        #expect(text[text.range(of: "甲")!][ListMarkerAttribute.self] == "1.")
        #expect(text[text.range(of: "乙")!][ListMarkerAttribute.self] == "2.")
        ParagraphEditing.apply("task", to: &text, selection: &selection)
        #expect(String(text.characters) == "甲\n乙")
        #expect(text[text.range(of: "甲")!][TaskStateAttribute.self] == false)
        selection = AttributedTextSelection(insertionPoint: text.startIndex)
        ParagraphEditing.toggleTask(in: &text, selection: &selection)
        #expect(String(text.characters) == "甲\n乙")
        #expect(text[text.range(of: "甲")!][TaskStateAttribute.self] == true)
        ParagraphEditing.apply("body", to: &text, selection: &selection)
        #expect(String(text.characters) == "甲\n乙")
        #expect(text[text.range(of: "甲")!][TaskStateAttribute.self] == nil)
        #expect(text[text.range(of: "乙")!][TaskStateAttribute.self] == false)
    }

    @Test func quoteContainsTaskAndKeepsCaretInPlace() throws {
        var text = MarkdownFormatting.render("> 12312321\n> 312312321")
        let caret = try #require(Range<AttributedString.Index>(NSRange(location: 4, length: 0), in: text))
        var selection = AttributedTextSelection(insertionPoint: caret.lowerBound)

        ParagraphEditing.apply("task", to: &text, selection: &selection)

        #expect(String(text.characters) == "12312321\n312312321")
        if case .insertionPoint(let restored) = selection.indices(in: text) {
            #expect(NSRange(restored..<restored, in: text).location == 4)
        } else {
            Issue.record("Expected the original caret instead of a selected paragraph")
        }
        let first = try #require(text.range(of: "12312321"))
        let second = try #require(text.range(of: "312312321"))
        #expect(text[first][ParagraphStyleAttribute.self] == "task")
        #expect(text[first][QuoteAttribute.self] == true)
        #expect(text[second][ParagraphStyleAttribute.self] == "body")
        #expect(text[second][QuoteAttribute.self] == true)
    }

    @Test func inputRulesContinueNumberingTasksAndNestedLists() {
        func match(_ source: String, _ input: String) -> MarkdownShortcut.Edit? {
            MarkdownShortcut.match(
                text: source, range: NSRange(location: source.utf16.count, length: 0), replacement: input, hasMarkedText: false)
        }
        #expect(match("1.", " ")?.style == .numbered)
        #expect(match("9. 完成", "\n")?.replacement == "\n10. ")
        #expect(match("\t• 子项", "\n")?.replacement == "\n\t• ")
        #expect(match("☑ 已完成", "\n")?.replacement == "\n☐ ")
        #expect(match("☐ ", "\n")?.style == .body)
        #expect(match("• [ ]", " ")?.replacement == "")
        #expect(match("```swift", "\n")?.style == .codeBlock)
    }
}
