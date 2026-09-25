import SwiftUI
import Testing

@testable import Weave

struct CodeBlockEditingTests {
    private func code(_ source: String, id: String = "sample") -> AttributedString {
        var text = AttributedString(source)
        text[CodeStyleAttribute.self] = "block:" + id
        text[CodeLanguageAttribute.self] = "swift"
        return text
    }

    @Test func blockExtentIncludesStyledRunsButExcludesAdjacentBlocks() {
        var text = code("let 🌊 = 1\nnext\n")
        text[text.range(of: "next")!].font = .body.bold()
        let length = String(text.characters).utf16.count
        text += code("other", id: "other")
        let selection = AttributedTextSelection(insertionPoint: text.range(of: "next")!.lowerBound)
        #expect(CodeBlockEditing.blockRange(in: text, selection: selection) == NSRange(location: 0, length: length))
        #expect(CodeBlockEditing.blockRange(in: text, selection: AttributedTextSelection(range: text.startIndex..<text.endIndex)) == nil)
        #expect(CodeBlockEditing.blockRange(in: AttributedString("plain"), selection: AttributedTextSelection()) == nil)
    }

    @Test func languageChangePreservesTextAndCaret() {
        var text = code("🌊\nprint(1)")
        var selection = AttributedTextSelection(insertionPoint: text.endIndex)
        CodeBlockEditing.setLanguage("custom-lang", in: &text, selection: &selection)
        #expect(text[CodeLanguageAttribute.self] == "custom-lang")
        #expect(selection.typingAttributes(in: text)[CodeLanguageAttribute.self] == "custom-lang")
        #expect(String(text.characters) == "🌊\nprint(1)")
        if case .insertionPoint(let caret) = selection.indices(in: text) {
            #expect(caret == text.endIndex)
        } else {
            Issue.record("Caret should remain collapsed")
        }
        #expect(CodeBlockEditing.languageTag(from: "```swift linenums") == "swift")
        #expect(CodeBlockEditing.languageTag(from: "~~~unknown") == "unknown")
        #expect(CodeBlockEditing.languageTag(from: "```") == "")
    }

    @Test func multilineIndentRoundTripPreservesAttributesAndUnicodeSelection() {
        var text = code("let 🌊 = 1\nprint(🌊)")
        let original = text
        var selection = AttributedTextSelection(range: text.startIndex..<text.endIndex)
        #expect(CodeBlockEditing.indent(in: &text, selection: &selection, outdent: false))
        #expect(String(text.characters) == "  let 🌊 = 1\n  print(🌊)")
        #expect(CodeBlockEditing.indent(in: &text, selection: &selection, outdent: true))
        #expect(text == original)
    }

    @Test func outdentHandlesTabsPartialSpacesAndSelectionEndingAtNextLineStart() {
        var text = code("\tfirst\n  second\nthird")
        let end = text.range(of: "third")!.lowerBound
        var selection = AttributedTextSelection(range: text.startIndex..<end)
        CodeBlockEditing.indent(in: &text, selection: &selection, outdent: true)
        #expect(String(text.characters) == "first\nsecond\nthird")
        CodeBlockEditing.indent(in: &text, selection: &selection, outdent: false)
        #expect(String(text.characters) == "  first\n  second\nthird")
    }

    @Test func tabOnTrailingEmptyCodeLineInsertsIndentWithBlockLanguage() {
        var text = code("let wave = 1\n")
        var selection = AttributedTextSelection(insertionPoint: text.endIndex)
        #expect(CodeBlockEditing.indent(in: &text, selection: &selection, outdent: false))
        #expect(String(text.characters) == "let wave = 1\n  ")
        #expect(text[CodeStyleAttribute.self] == "block:sample")
        #expect(text[CodeLanguageAttribute.self] == "swift")
        if case .insertionPoint(let caret) = selection.indices(in: text) {
            #expect(caret == text.endIndex)
        } else {
            Issue.record("Caret should follow indentation")
        }
        CodeBlockEditing.indent(in: &text, selection: &selection, outdent: true)
        #expect(String(text.characters) == "let wave = 1\n")
    }

    @Test func newlineContinuesLeadingWhitespaceOnlyInsideCode() {
        let text = code("  \tprint(🌊)")
        #expect(CodeBlockEditing.newline(in: text, selection: AttributedTextSelection(insertionPoint: text.endIndex)) == "\n  \t")
        #expect(CodeBlockEditing.newline(in: text, selection: AttributedTextSelection(range: text.startIndex..<text.endIndex)) == nil)
        let plain = AttributedString("plain")
        #expect(CodeBlockEditing.newline(in: plain, selection: AttributedTextSelection(insertionPoint: plain.endIndex)) == nil)
        var editable = plain
        var selection = AttributedTextSelection(insertionPoint: plain.endIndex)
        #expect(!CodeBlockEditing.indent(in: &editable, selection: &selection, outdent: false))
    }

    @Test func lexerConsumesStringsCommentsAndUnicodeAsWholeTokens() {
        let source = "let wave = \"🌊 if 123\" // return 2\nvar value = 42"
        let tokens = CodeBlockEditing.tokens(source: source, language: "swift")
        let native = source as NSString
        #expect(tokens.map { native.substring(with: $0.range) } == ["let", "\"🌊 if 123\"", "// return 2", "var", "42"])
        #expect(tokens.map(\.kind) == [.keyword, .string, .comment, .keyword, .number])
        #expect(CodeBlockEditing.tokens(source: source, language: "unknown").isEmpty)
    }

    @Test func supportedLanguagesAndAliasesRecognizeTheirSyntax() {
        for language in ["javascript", "js", "typescript", "ts"] {
            #expect(
                CodeBlockEditing.tokens(source: "const x = `if 1`; /* let 4 */", language: language).map(\.kind) == [
                    .keyword, .string, .comment,
                ])
        }
        for language in ["python", "py"] {
            #expect(
                CodeBlockEditing.tokens(source: "def x(): # return 1\n  return '''if 3'''", language: language).map(\.kind) == [
                    .keyword, .comment, .keyword, .string,
                ])
        }
        #expect(
            CodeBlockEditing.tokens(source: "{\"null\": true, \"n\": 1.5e2}", language: "json").map(\.kind) == [
                .string, .keyword, .string, .number,
            ])
        for language in ["shell", "sh", "bash", "zsh"] {
            #expect(
                CodeBlockEditing.tokens(source: "if true; then # comment", language: language).map(\.kind) == [
                    .keyword, .keyword, .comment,
                ])
        }
        #expect(CodeBlockEditing.tokens(source: "let x = \"unterminated if", language: "swift").map(\.kind) == [.keyword, .string])
        #expect(CodeBlockEditing.tokens(source: "/* unterminated let", language: "swift").map(\.kind) == [.comment])
    }
    @Test(arguments: [
        ("go", "func"), ("rust", "fn"), ("java", "class"), ("kotlin", "fun"),
        ("c", "typedef"), ("cpp", "namespace"), ("csharp", "using"),
        ("ruby", "def"), ("php", "echo"), ("sql", "SELECT"),
        ("html", "<div"), ("xml", "<root"), ("css", ".item{"),
        ("scss", "$color:"), ("less", "@color:"), ("yaml", "name:"),
        ("markdown", "# Heading"), ("graphql", "query"),
        ("jsx", "<Component"), ("tsx", "interface"),
    ])
    func expandedLanguagesRecognizeSyntax(language: String, source: String) {
        let tokens = CodeBlockEditing.tokens(source: source, language: language)
        #expect(tokens.contains { $0.kind == .keyword })
        #expect(CodeBlockEditing.languages.contains { $0.id == language })
    }

    @Test func aliasesShareRulesAndCommentsProtectKeywords() {
        for alias in ["rs", "kt", "c++", "cs", "rb", "golang", "gql", "yml", "md", "htm"] {
            let canonical = CodeBlockEditing.canonicalLanguage(alias)
            #expect(CodeBlockEditing.languages.contains { $0.id == canonical })
        }
        #expect(CodeBlockEditing.tokens(source: "-- SELECT 42", language: "sql").map(\.kind) == [.comment])
        #expect(CodeBlockEditing.tokens(source: "<!-- <div> 42 -->", language: "html").map(\.kind) == [.comment])
        #expect(CodeBlockEditing.tokens(source: "/* color: 42 */", language: "css").map(\.kind) == [.comment])
    }

}
