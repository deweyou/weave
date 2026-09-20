import Foundation
import Testing

@testable import Weave

struct EditorInputFeaturesTests {
    @Test func standardRegistryRoutesIndependentFeatureCommands() throws {
        let registry = EditorFeatureRegistry()

        let link = context(text: "label", range: NSRange(location: 0, length: 5), replacement: "https://apple.com")
        #expect(registry.command(for: link) == .applyLink(try #require(URL(string: "https://apple.com"))))

        let code = context(text: "let value = 1", codeStyle: "block:test", replacement: "\t")
        #expect(registry.command(for: code) == .indentCode(outdent: false))

        let plain = context(text: "body", replacement: "x")
        #expect(registry.command(for: plain) == nil)
    }

    @Test func taskFeatureContinuesContentAndExitsItsEmptyParagraph() {
        let registry = EditorFeatureRegistry()
        let continued = context(text: "Task", role: "task", replacement: "\n")
        #expect(
            registry.command(for: continued)
                == .edit(
                    .init(range: NSRange(location: 4, length: 0), replacement: "\n", style: .task),
                    origin: .feature))

        let exited = context(text: "Task\n", role: "task", replacement: "\n")
        #expect(
            registry.command(for: exited)
                == .edit(
                    .init(range: NSRange(location: 5, length: 0), replacement: "", style: .body),
                    origin: .feature))
    }

    @Test func quotedMarkdownShortcutOverridesQuoteContinuationAndKeepsOuterQuote() {
        let registry = EditorFeatureRegistry()
        let task = context(text: "[]", isQuoted: true, replacement: " ")
        #expect(
            registry.command(for: task)
                == .edit(
                    .init(range: NSRange(location: 0, length: 2), replacement: "", style: .task),
                    origin: .markdownShortcut))

        let emptyList = context(text: "• ", isQuoted: true, replacement: "\n")
        #expect(
            registry.command(for: emptyList)
                == .edit(
                    .init(range: NSRange(location: 0, length: 2), replacement: "", style: .quote),
                    origin: .markdownShortcut))
    }

    @Test func customFeatureCanBeRegisteredWithoutNativeViewAccess() {
        let registry = EditorFeatureRegistry(features: [
            ConsumeAtSignFeature(id: "late", priority: 200), ConsumeAtSignFeature(id: "early", priority: 100),
        ])
        #expect(registry.features.map(\.id) == ["early", "late"])
        #expect(registry.command(for: context(text: "", replacement: "@")) == .consume)
        #expect(registry.command(for: context(text: "", replacement: "x")) == nil)
    }

    private func context(
        text: String,
        role: String? = nil,
        codeStyle: String? = nil,
        isQuoted: Bool = false,
        range: NSRange? = nil,
        replacement: String,
        selection: NSRange? = nil
    ) -> EditorInputContext {
        let storage = NSMutableAttributedString(string: text)
        var attributes: [NSAttributedString.Key: Any] = [:]
        if let role { attributes[.weaveParagraphStyle] = role }
        if let codeStyle { attributes[.weaveCodeStyle] = codeStyle }
        if isQuoted { attributes[.weaveQuote] = true }
        if storage.length > 0 { storage.addAttributes(attributes, range: NSRange(location: 0, length: storage.length)) }
        let inputRange = range ?? NSRange(location: storage.length, length: 0)
        return EditorInputContext(
            storage: storage,
            typingAttributes: attributes,
            range: inputRange,
            replacement: replacement,
            selection: selection ?? inputRange)
    }
}

private struct ConsumeAtSignFeature: EditorInputFeature {
    let id: String
    let priority: Int

    func command(for context: EditorInputContext) -> EditorInputCommand? {
        context.replacement == "@" ? .consume : nil
    }
}
