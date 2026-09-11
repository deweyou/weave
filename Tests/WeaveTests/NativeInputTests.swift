#if os(macOS)
import AppKit
import SwiftUI
import Testing
@testable import Weave

@MainActor
struct NativeInputTests {
    private func editor(_ source: AttributedString) -> (NSTextView, NativeRichTextEditor.Coordinator) {
        var text = source
        var selection = AttributedTextSelection(insertionPoint: source.endIndex)
        let editor = NativeRichTextEditor(text: Binding(get: { text }, set: { text = $0 }), selection: Binding(get: { selection }, set: { selection = $0 }))
        let coordinator = editor.makeCoordinator()
        let view = NSTextView()
        let native = NativeTextAttributes.native(source, context: EnvironmentValues().fontResolutionContext)
        view.textStorage?.setAttributedString(native)
        view.setSelectedRange(NSRange(location: native.length, length: 0))
        if native.length > 0 { view.typingAttributes = native.attributes(at: native.length - 1, effectiveRange: nil) }
        coordinator.textView = view
        return (view, coordinator)
    }

    @Test func headingReturnResetsTypingStyleWithoutChangingHeading() {
        let (view, coordinator) = editor(MarkdownFormatting.render("# 标题"))
        #expect(!coordinator.intercept(range: view.selectedRange(), replacement: "\n"))
        #expect(view.string == "标题\n")
        #expect(view.typingAttributes[.weaveParagraphStyle] as? String == "body")
        #expect(view.textStorage?.attribute(.weaveParagraphStyle, at: 0, effectiveRange: nil) as? String == "heading:1")
    }

    @Test func listBackspaceRemovesPrefixWithoutDeletingText() {
        let (view, coordinator) = editor(AttributedString("• 任务"))
        view.setSelectedRange(NSRange(location: 2, length: 0))
        #expect(!coordinator.intercept(range: NSRange(location: 1, length: 1), replacement: ""))
        #expect(view.string == "任务")
        #expect(view.selectedRange().location == 0)
    }

    @Test func codeEntryAndEmptyLineExitKeepNativeTypingState() {
        let (view, coordinator) = editor(AttributedString("```swift"))
        #expect(!coordinator.intercept(range: view.selectedRange(), replacement: "\n"))
        #expect(view.string.isEmpty)
        #expect((view.typingAttributes[.weaveCodeStyle] as? String)?.hasPrefix("block:") == true)
        #expect(!coordinator.intercept(range: view.selectedRange(), replacement: "\n"))
        #expect(view.typingAttributes[.weaveCodeStyle] == nil)
    }

    @Test func pastedURLKeepsSelectedLabel() {
        let (view, coordinator) = editor(AttributedString("网站"))
        view.setSelectedRange(NSRange(location: 0, length: 2))
        #expect(!coordinator.intercept(range: view.selectedRange(), replacement: "https://apple.com"))
        #expect(view.string == "网站")
        #expect(view.textStorage?.attribute(.link, at: 0, effectiveRange: nil) as? URL == URL(string: "https://apple.com"))
    }

    @Test func boldShortcutAfterChineseTextOnlyFormatsMarkedContent() {
        let (view, coordinator) = editor(AttributedString("正文**加粗*"))
        #expect(!coordinator.intercept(range: view.selectedRange(), replacement: "*"))
        #expect(view.string == "正文加粗")
        let font = view.textStorage!.attribute(.font, at: 2, effectiveRange: nil) as! NSFont
        #expect(NSFontManager.shared.traits(of: font).contains(.boldFontMask))
        let bodyFont = view.typingAttributes[.font] as! NSFont
        #expect(!NSFontManager.shared.traits(of: bodyFont).contains(.boldFontMask))
    }

    @Test func exitingPopulatedCodeBlockPersistsBodyBoundary() {
        var source = AttributedString("let value = 1\n")
        source.font = .body.monospaced()
        source[CodeStyleAttribute.self] = "block:test"
        source[ParagraphStyleAttribute.self] = "code"
        let (view, coordinator) = editor(source)
        #expect(!coordinator.intercept(range: view.selectedRange(), replacement: "\n"))
        #expect(view.typingAttributes[.weaveCodeStyle] == nil)
        let boundary = view.textStorage!.length - 1
        #expect(view.textStorage!.attribute(.weaveCodeStyle, at: boundary, effectiveRange: nil) == nil)
        #expect(view.textStorage!.attribute(.weaveCodeStyle, at: 0, effectiveRange: nil) as? String == "block:test")
    }
}
#endif
