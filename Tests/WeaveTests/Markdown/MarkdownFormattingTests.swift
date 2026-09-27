import SwiftUI
import Testing

@testable import Weave

struct MarkdownFormattingTests {
    @Test @MainActor func closingFenceDoesNotLeakCodeIntoFollowingEmptyParagraph() {
        let context = EnvironmentValues().fontResolutionContext
        let text = MarkdownFormatting.render("```swift\nlet value = 1\n```\n")
        let native = NativeTextAttributes.native(text, context: context)
        #expect(native.attribute(.weaveCodeStyle, at: native.length - 1, effectiveRange: nil) == nil)
        #expect(native.attribute(.weaveParagraphStyle, at: native.length - 1, effectiveRange: nil) as? String == "body")
        #expect(MarkdownFormatting.serialize(NativeTextAttributes.rich(native), context: context) == "```swift\nlet value = 1\n```\n")
    }

    @MainActor @Test func paragraphSeparatorsAndExplicitBlankParagraphsRoundTripWithoutAccumulating() throws {
        let context = EnvironmentValues().fontResolutionContext
        for (source, expected) in [
            ("First\n\nSecond", "First\nSecond"),
            ("First\n\n\nSecond", "First\n\nSecond"),
            ("# Heading\n\nBody", "Heading\nBody"),
            ("First\nsecond\n\nThird", "First\u{2028}second\nThird"),
            ("\nFirst\n\n", "\nFirst\n\n"),
        ] {
            var text = MarkdownFormatting.render(source)
            #expect(String(text.characters) == expected)
            for _ in 0..<3 {
                var note = Note(id: UUID(), text: "", createdAt: Date(), updatedAt: Date())
                note.richText = NativeTextAttributes.rich(NativeTextAttributes.native(text, context: context))
                let restored = try JSONDecoder().decode(Note.self, from: JSONEncoder().encode(note))
                text = MarkdownFormatting.render(MarkdownFormatting.serialize(restored.richText, context: context))
                #expect(String(text.characters) == expected)
            }
        }
    }

    @MainActor @Test func hardLineBreaksPreserveInlineFormattingAndDoNotCreateParagraphs() {
        let context = EnvironmentValues().fontResolutionContext
        for literal in ["First\u{2028}second", "First\u{2028}\u{2028}third", "First\u{2028}", "\u{2028}Last"] {
            var text = AttributedString(literal)
            text.font = .body.bold()
            text[InlineEmphasisAttribute.self] = 1
            let markdown = MarkdownFormatting.serialize(text, context: context)
            #expect(markdown.contains("  \n"))
            let restored = MarkdownFormatting.render(markdown)
            #expect(String(restored.characters) == literal)
            #expect(!String(restored.characters).contains("\n"))
            if let word = restored.range(of: "First") {
                #expect(restored[word][InlineEmphasisAttribute.self] == 1)
            }
        }
    }

    @Test func formatsCommonSyntaxAndPreservesChineseParagraphs() {
        let result = MarkdownFormatting.render("# 中文标题\n\n**加粗** 与 *斜体*\n- 列表\n> 引用\n1. 第一项\n- [x] 完成")
        #expect(String(result.characters) == "中文标题\n加粗 与 斜体\n列表\n引用\n第一项\n完成")
        #expect(result[result.range(of: "引用")!][QuoteAttribute.self] == true)
        #expect(result[result.range(of: "完成")!][TaskStateAttribute.self] == true)
        let title = result.range(of: "中文标题")!
        #expect(result[title].font == ParagraphEditing.font(for: "heading:1"))
        let bold = result.range(of: "加粗")!
        #expect(result[bold].font == Font.body.bold())
        let italic = result.range(of: "斜体")!
        #expect(result[italic].font == Font.body.italic())
    }

    @Test func preservesCodeLiterallyAndLinkDestination() {
        let result = MarkdownFormatting.render("```\n**literal**\n```\n[Apple](https://apple.com)")
        #expect(String(result.characters) == "**literal**\nApple")
        #expect(result[result.range(of: "**literal**")!].font == Font.body.monospaced())
        #expect(result[result.range(of: "Apple")!].link == URL(string: "https://apple.com"))
    }

    @MainActor @Test func quoteComposesWithRichBlocksAndShortcuts() {
        let source = "> **粗体**\n> - 项目\n> 1. 顺序\n> - [x] 完成\n> ```swift\n> let value = 1\n> ```"
        let text = MarkdownFormatting.render(source)
        for word in ["粗体", "项目", "顺序", "完成", "let value = 1"] {
            #expect(text[text.range(of: word)!][QuoteAttribute.self] == true)
        }
        #expect(text[text.range(of: "粗体")!][InlineEmphasisAttribute.self] == 1)
        #expect(text[text.range(of: "项目")!][ParagraphStyleAttribute.self] == "bullet")
        #expect(text[text.range(of: "顺序")!][ParagraphStyleAttribute.self] == "numbered")
        #expect(text[text.range(of: "完成")!][ParagraphStyleAttribute.self] == "task")
        #expect(text[text.range(of: "完成")!][TaskStateAttribute.self] == true)
        #expect(text[text.range(of: "let value = 1")!][CodeStyleAttribute.self]?.hasPrefix("block:") == true)
        let markdown = MarkdownFormatting.serialize(text, context: EnvironmentValues().fontResolutionContext)
        #expect(markdown == source)
        #expect(String(MarkdownFormatting.render(markdown).characters) == String(text.characters))
    }

    @Test func unfinishedFenceAndEscapedSyntaxRemainReadable() {
        #expect(String(MarkdownFormatting.render("```\n草稿").characters) == "```\u{2028}草稿")
        #expect(String(MarkdownFormatting.render("\\*普通文字\\*").characters) == "*普通文字*")
        #expect(String(MarkdownFormatting.render("").characters).isEmpty)
    }
}

extension MarkdownFormattingTests {
    @MainActor @Test func roundTripsSupportedStylesAndIndentation() {
        let source =
            "# Title\n###### Small\n**bold** *italic* ~~removed~~ [Link](https://example.com) `x * y`\n- item\n\t- [x] done\n12. numbered\n> quote"
        let first = MarkdownFormatting.render(source)
        let exported = MarkdownFormatting.serialize(first, context: EnvironmentValues().fontResolutionContext)
        let second = MarkdownFormatting.render(exported)
        #expect(String(second.characters) == String(first.characters))
        #expect(second[second.range(of: "bold")!].font == Font.body.bold())
        #expect(second[second.range(of: "italic")!].font == Font.body.italic())
        #expect(second[second.range(of: "removed")!].strikethroughStyle == .single)
        #expect(second[second.range(of: "Small")!][ParagraphStyleAttribute.self] == "heading:6")
        #expect(!exported.contains("**Small**"))
    }

    @MainActor @Test func escapesLiteralMarkdownAndPreservesUnicode() {
        let literal = "# text\n1. plain\n**stars** [label](url) ![image](url)\\path 👩🏽‍💻 中文"
        let text = AttributedString(literal)
        let exported = MarkdownFormatting.serialize(text, context: EnvironmentValues().fontResolutionContext)
        #expect(String(MarkdownFormatting.render(exported).characters) == literal)
    }

    @MainActor @Test func roundTripsVariableFencesAndBlankCodeLines() {
        let source = "````swift\nlet marker = \"```\"\n\n**literal**\n````\nafter"
        let text = MarkdownFormatting.render(source)
        let exported = MarkdownFormatting.serialize(text, context: EnvironmentValues().fontResolutionContext)
        #expect(exported.hasPrefix("````swift\n"))
        #expect(String(MarkdownFormatting.render(exported).characters) == String(text.characters))
        #expect(String(text.characters) == "let marker = \"```\"\n\n**literal**\nafter")
    }

    @MainActor @Test func inlineCodeWithBackticksRoundTrips() {
        var text = AttributedString("`x` and ``y``")
        text[CodeStyleAttribute.self] = "inline"
        text.font = .body.monospaced()
        let exported = MarkdownFormatting.serialize(text, context: EnvironmentValues().fontResolutionContext)
        #expect(String(MarkdownFormatting.render(exported).characters) == String(text.characters))
    }

    @Test func unsupportedImagesRemainVisible() {
        let source = "Before ![description](https://example.com/image.png) after"
        #expect(String(MarkdownFormatting.render(source).characters) == source)
    }
}

extension MarkdownFormattingTests {
    @MainActor @Test func serializesNativeBridgeStylesAndWhitespaceBoundaries() {
        let context = EnvironmentValues().fontResolutionContext
        let imported = MarkdownFormatting.render("### Heading\n**bold** and *italic*\n> quote\n- [ ] task")
        let restored = NativeTextAttributes.rich(NativeTextAttributes.native(imported, context: context))
        let exported = MarkdownFormatting.serialize(restored, context: context)
        #expect(exported.contains("### Heading"))
        #expect(exported.contains("**bold**"))
        #expect(exported.contains("*italic*"))
        #expect(String(MarkdownFormatting.render(exported).characters) == String(imported.characters))

        var text = AttributedString(" bold text ")
        text.font = .body.bold()
        text[text.range(of: "text")!].foregroundColor = .red
        let markdown = MarkdownFormatting.serialize(text, context: context)
        #expect(markdown == " **bold text** ")
        #expect(String(MarkdownFormatting.render(markdown).characters) == " bold text ")
    }

    @MainActor @Test func preservesEmptyAndTrailingParagraphs() {
        let context = EnvironmentValues().fontResolutionContext
        for source in ["", "\n", "text\n\n", "````\n```\n`````", "```\nunfinished", "```\n```"] {
            let text = MarkdownFormatting.render(source)
            let exported = MarkdownFormatting.serialize(text, context: context)
            #expect(String(MarkdownFormatting.render(exported).characters) == String(text.characters))
        }
    }
}

extension MarkdownFormattingTests {
    @MainActor @Test func combinedInlineStylesAndLinkedRunsRoundTrip() {
        let context = EnvironmentValues().fontResolutionContext
        var text = AttributedString("before link after")
        text.font = .body.bold().italic()
        text[text.range(of: "link")!].link = URL(string: "https://example.com")
        let exported = MarkdownFormatting.serialize(text, context: context)
        let restored = MarkdownFormatting.render(exported)
        #expect(String(restored.characters) == String(text.characters))
        #expect(exported == "***before*** [***link***](https://example.com) ***after***")
        let linked = restored[restored.range(of: "link")!]
        #expect(linked.link == URL(string: "https://example.com"))
        #expect(linked.inlinePresentationIntent?.contains(.stronglyEmphasized) == true)
        #expect(linked.font?.resolve(in: context).isBold == true)
        #expect(linked.font?.resolve(in: context).isItalic == true)
    }

    @MainActor @Test func normalizesImportedListIndentationAndExportsLegacyNumbering() {
        let text = MarkdownFormatting.render("    - nested\n  - [ ] task")
        #expect(String(text.characters) == "\tnested\n\ttask")
        var legacy = AttributedString("3. existing")
        legacy[ParagraphStyleAttribute.self] = "body"
        #expect(MarkdownFormatting.serialize(legacy, context: EnvironmentValues().fontResolutionContext) == "3. existing")
    }
}

extension MarkdownFormattingTests {
    @Test func preservesUnsupportedMarkupAndImageSyntaxInsideCode() {
        #expect(String(MarkdownFormatting.render("`![x](url)`").characters) == "![x](url)")
        let source = "<span>literal</span> ![**description**](image.png)"
        #expect(String(MarkdownFormatting.render(source).characters) == source)
    }
}

extension MarkdownFormattingTests {
    @Test func inlineCodeAndLinksDoNotStyleParagraphBreaks() {
        let text = MarkdownFormatting.render("`literal`\n\n[link](https://example.com)\nnext")
        for run in text.runs where String(text[run.range].characters).contains("\n") {
            #expect(run[CodeStyleAttribute.self] == nil)
            #expect(run.link == nil)
        }
        #expect(text[text.range(of: "literal")!][CodeStyleAttribute.self] == "inline")
    }
}

extension MarkdownFormattingTests {
    @MainActor
    @Test(
        arguments: ["", "# ", "###### ", "> ", "> ### ", "- ", "1. ", "- [ ] ", "> - "],
        [
            "**内容🌿**", "*内容🌿*", "~~内容🌿~~", "`内容🌿`", "***内容🌿***", "~~**内容🌿**~~", "[***内容🌿***](https://example.com)",
            "[~~内容🌿~~](https://example.com)",
        ])
    func nestedRichBlocksSurviveNativeAndMarkdownRoundTrips(block: String, inline: String) throws {
        let source = MarkdownFormatting.render(block + inline)
        #expect(String(source.characters) == "内容🌿")
        let context = EnvironmentValues().fontResolutionContext
        let native = NativeTextAttributes.native(source, context: context)
        let bridged = NativeTextAttributes.rich(native)
        let serialized = MarkdownFormatting.serialize(bridged, context: context)
        let restored = MarkdownFormatting.render(serialized)
        #expect(String(restored.characters) == "内容🌿")
        let original = try #require(source.runs.first)
        let result = try #require(restored.runs.first)
        #expect(result[ParagraphStyleAttribute.self] == original[ParagraphStyleAttribute.self])
        #expect(result[QuoteAttribute.self] == original[QuoteAttribute.self])
        #expect(result[TaskStateAttribute.self] == original[TaskStateAttribute.self])
        #expect(result[ListMarkerAttribute.self] == original[ListMarkerAttribute.self])
        #expect(result.link == original.link)
        #expect(result.strikethroughStyle == original.strikethroughStyle)
        #expect(result.font?.resolve(in: context).isBold == original.font?.resolve(in: context).isBold)
        #expect(result.font?.resolve(in: context).isItalic == original.font?.resolve(in: context).isItalic)
        #expect(result[CodeStyleAttribute.self] == original[CodeStyleAttribute.self])
    }

    @MainActor @Test(arguments: ["**加粗**", "*斜体*", "~~删除线~~", "[链接](https://example.com)", "- 列表", "# 标题", "[] 待办"])
    func codeBlockAndInlineCodeKeepNestedSyntaxLiteral(syntax: String) {
        let context = EnvironmentValues().fontResolutionContext
        for markdown in ["```swift\n" + syntax + "\n```", "`" + syntax + "`"] {
            let source = MarkdownFormatting.render(markdown)
            #expect(String(source.characters) == syntax)
            #expect(source.runs.allSatisfy { $0.link == nil && $0.strikethroughStyle == nil })
            let restored = MarkdownFormatting.render(MarkdownFormatting.serialize(source, context: context))
            #expect(String(restored.characters) == syntax)
            #expect(restored.runs.allSatisfy { $0[CodeStyleAttribute.self] != nil })
        }
    }

    @MainActor @Test func underlineComposesWithBoldItalicStrikeAndLinkInNativeClipboard() throws {
        var source = AttributedString("中文🌿")
        source.font = .body.bold().italic()
        source.underlineStyle = .single
        source.strikethroughStyle = .single
        source.link = URL(string: "https://example.com")
        source[QuoteAttribute.self] = true
        source[ParagraphStyleAttribute.self] = "heading:2"
        let context = EnvironmentValues().fontResolutionContext
        let bridged = NativeTextAttributes.rich(NativeTextAttributes.native(source, context: context))
        let restored = try RichTextClipboard.decode(RichTextClipboard.encode(bridged))
        let run = try #require(restored.runs.first)
        #expect(run.underlineStyle == .single)
        #expect(run.strikethroughStyle == .single)
        #expect(run.font?.resolve(in: context).isBold == true)
        #expect(run.font?.resolve(in: context).isItalic == true)
        #expect(run.link == source.link)
        #expect(run[QuoteAttribute.self] == true)
        #expect(run[ParagraphStyleAttribute.self] == "heading:2")
    }
}
