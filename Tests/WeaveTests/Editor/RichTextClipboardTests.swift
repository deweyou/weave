import SwiftUI
import Testing

@testable import Weave

struct RichTextClipboardTests {
    @Test @MainActor func structuredClipboardPreservesHeadingAndInlineEmphasisIndependently() throws {
        let source = "## Plain **Strong** *Italic*"
        let rendered = MarkdownFormatting.render(source)
        let restored = try RichTextClipboard.decode(RichTextClipboard.encode(rendered))
        #expect(restored[restored.range(of: "Plain")!][InlineEmphasisAttribute.self] == 0)
        #expect(restored[restored.range(of: "Strong")!][InlineEmphasisAttribute.self] == 1)
        #expect(restored[restored.range(of: "Italic")!][InlineEmphasisAttribute.self] == 2)
        #expect(MarkdownFormatting.serialize(restored, context: EnvironmentValues().fontResolutionContext) == source)
    }

    @Test func eachPasteCreatesFreshTableAndBlockIdentitiesWithoutChangingContent() throws {
        let table = TableData(rows: [["Key", "Value"], ["🌊", "e\u{301} | \\ path"]], alignments: [.left, .right])
        var code = AttributedString("let wave = \"🌊\"\nprint(wave)")
        code[CodeStyleAttribute.self] = "block:original"
        code[CodeLanguageAttribute.self] = "swift"
        code[ParagraphStyleAttribute.self] = "code"
        code.font = .body.monospaced()
        code[code.range(of: "wave")!].font = .body.monospaced().bold()
        let original = table.attributedText + AttributedString("\n") + code
        let encoded = try RichTextClipboard.encode(original)
        let first = try RichTextClipboard.decode(encoded)
        let second = try RichTextClipboard.decode(encoded)
        let firstTable = try #require(first.runs.compactMap { $0[TableAttribute.self] }.first)
        let secondTable = try #require(second.runs.compactMap { $0[TableAttribute.self] }.first)
        #expect(firstTable.id != table.id)
        #expect(firstTable.id != secondTable.id)
        #expect(firstTable.rows == table.rows)
        #expect(firstTable.alignments == table.alignments)
        #expect(String(first.characters) == String(original.characters))
        let firstIDs = Set(first.runs.compactMap { $0[CodeStyleAttribute.self] })
        let secondIDs = Set(second.runs.compactMap { $0[CodeStyleAttribute.self] })
        #expect(firstIDs.count == 1)
        #expect(firstIDs != ["block:original"])
        #expect(firstIDs.isDisjoint(with: secondIDs))
        #expect(first[first.range(of: "wave")!].font == .body.monospaced().bold())
        #expect(first.runs.filter { $0[CodeStyleAttribute.self] != nil }.allSatisfy { $0[CodeLanguageAttribute.self] == "swift" })
    }

    @Test func distinctBlocksStayDistinctAndInlineCodeKeepsItsRole() throws {
        func code(_ literal: String, style: String) -> AttributedString {
            var text = AttributedString(literal)
            text[CodeStyleAttribute.self] = style
            return text
        }
        let original =
            code("one", style: "block:first") + AttributedString("\n") + code("two", style: "block:second") + AttributedString("\n")
            + code("three", style: "inline")
        let pasted = try RichTextClipboard.decode(RichTextClipboard.encode(original))
        let roles = pasted.runs.compactMap { $0[CodeStyleAttribute.self] }
        #expect(Set(roles).count == 3)
        #expect(roles.last == "inline")
        #expect(!roles.contains("block:first"))
        #expect(!roles.contains("block:second"))
    }

    @Test func plainTextStylesAndEmptyPayloadRoundTrip() throws {
        var text = AttributedString("emoji 👩🏽‍💻 and link")
        text.font = .title2.bold()
        text.foregroundColor = .blue
        text.underlineStyle = .single
        text[text.range(of: "link")!].link = URL(string: "https://example.com")
        #expect(try RichTextClipboard.decode(RichTextClipboard.encode(text)) == text)
        #expect(try RichTextClipboard.decode(RichTextClipboard.encode(AttributedString())) == AttributedString())
    }

    @Test func malformedOrUnknownPayloadsThrow() throws {
        for invalid in ["not-json", "{}", "{\"version\":2,\"richText\":\"text\"}", "{\"version\":1,\"richText\":42}"] {
            #expect(throws: (any Error).self) { try RichTextClipboard.decode(Data(invalid.utf8)) }
        }
        var invalidTable = AttributedString("not an attachment")
        invalidTable[TableAttribute.self] = TableData()
        #expect(throws: RichTextClipboard.ClipboardError.invalidTableRange) { try RichTextClipboard.encode(invalidTable) }

        // Encode through the same public scope to simulate a malformed external clipboard producer.
        struct UncheckedPayload: Encodable {
            let text: AttributedString
            enum CodingKeys: CodingKey { case version, richText }
            func encode(to encoder: any Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(1, forKey: .version)
                try container.encode(text, forKey: .richText, configuration: NoteAttributeScope.self)
            }
        }
        let malformed = try JSONEncoder().encode(UncheckedPayload(text: invalidTable))
        #expect(throws: RichTextClipboard.ClipboardError.invalidTableRange) { try RichTextClipboard.decode(malformed) }
        var combined = AttributedString("\u{FFFC}\u{FFFC}")
        combined[TableAttribute.self] = TableData()
        #expect(throws: RichTextClipboard.ClipboardError.invalidTableRange) { try RichTextClipboard.encode(combined) }
    }
}
