import SwiftUI
import Testing

@testable import Weave

struct TableDataTests {
    @Test func editingMaintainsRectangularShapeAndOneHeader() {
        var table = TableData(rows: [["Name", "Value"], ["Alpha", "1"]])
        table.insertColumn(after: 0)
        table.insertRow(after: 1)
        #expect(table.rows == [["Name", "", "Value"], ["Alpha", "", "1"], ["", "", ""]])
        table.removeColumn(at: 0)
        table.removeRow(at: 1)
        #expect(table.rows == [["", "Value"], ["", ""]])
        table.removeRow(at: 0)
        table.removeRow(at: 0)
        table.removeColumn(at: 0)
        table.removeColumn(at: 0)
        #expect(table.rows == [[""]])
    }

    @Test func tableMarkdownRoundTripsEscapesAlignmentAndEmptyCells() throws {
        let table = TableData(rows: [["Name", "Value", ""], ["a|b", "\\path", "👩🏽‍💻"]], alignments: [.left, .center, .right])
        let parsed = try #require(TableData.parse(lines: table.markdown.components(separatedBy: "\n"), at: 0))
        #expect(parsed.table.rows == table.rows)
        #expect(parsed.table.alignments == table.alignments)
        #expect(parsed.count == 3)
        #expect(TableData.parse(lines: ["a | b", "--- | --- | ---"], at: 0) == nil)
        #expect(TableData.parse(lines: ["a | b", "text | text"], at: 0) == nil)
    }

    @MainActor @Test func documentRoundTripsTableThroughMarkdownAndNativeBridge() throws {
        let source = "Before\n| Key | Value |\n| --- | ---: |\n| Alpha | 42 |\nAfter"
        let text = MarkdownFormatting.render(source)
        #expect(TableData.plainText(in: text) == "Before\nKey\tValue\nAlpha\t42\nAfter")
        let context = EnvironmentValues().fontResolutionContext
        let native = NativeTextAttributes.native(text, context: context)
        let restored = NativeTextAttributes.rich(native)
        let table = try #require(restored.runs.compactMap { $0[TableAttribute.self] }.first)
        #expect(table.rows == [["Key", "Value"], ["Alpha", "42"]])
        #expect(
            MarkdownFormatting.serialize(restored, context: context)
                == source.replacingOccurrences(of: "Before\n", with: "Before\n\n").replacingOccurrences(of: "\nAfter", with: "\n\nAfter"))
    }

    @Test func tableContentParticipatesInSearchProjectionAndPersistence() throws {
        var note = Note(id: UUID(), text: "", createdAt: Date(), updatedAt: Date())
        note.richText = TableData(rows: [["Title"], ["Find me"]], alignments: [.left]).attributedText
        #expect(note.text == "Title\nFind me")
        #expect(note.title.isEmpty)
        #expect(note.preview == "Title Find me")
        let restored = try JSONDecoder().decode(Note.self, from: JSONEncoder().encode(note))
        #expect(restored.richText == note.richText)
        #expect(restored.text.contains("Find me"))
    }

    @Test func markdownConversionPreservesExistingTableAndLiteralCode() {
        let table = TableData(rows: [["Key"], ["Value"]], alignments: [.left])
        let code = MarkdownFormatting.render("```swift\n**literal**\n```")
        let original = AttributedString("# Heading\n") + table.attributedText + AttributedString("\n") + code
        let converted = MarkdownFormatting.renderKeepingBlocks(original)
        #expect(converted.runs.compactMap { $0[TableAttribute.self] }.first == table)
        #expect(TableData.plainText(in: converted) == "Heading\nKey\nValue\n**literal**")
        #expect(converted.runs.last?[CodeLanguageAttribute.self] == "swift")
    }

    @Test func malformedPersistedTableFailsDecoding() throws {
        let source = "{\"id\":\"00000000-0000-0000-0000-000000000000\",\"rows\":[[\"a\"]],\"alignments\":[]}"
        #expect(throws: (any Error).self) { try JSONDecoder().decode(TableData.self, from: Data(source.utf8)) }
    }
}
