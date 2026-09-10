import SwiftUI
import Testing
@testable import Weave
#if os(macOS)
import AppKit

struct ReadingLayoutTests {
    @Test @MainActor func fontScalingDoesNotAccumulateAcrossEdits() {
        let context = EnvironmentValues().fontResolutionContext
        var text = MarkdownFormatting.render("# 标题\n正文 **强调** [链接](https://apple.com)")
        let initial = NativeTextAttributes.native(text, context: context)
        for _ in 0..<5 {
            text = NativeTextAttributes.rich(NativeTextAttributes.native(text, context: context))
        }
        let final = NativeTextAttributes.native(text, context: context)
        #expect(initial.string == final.string)
        for index in 0..<initial.length {
            let before = initial.attribute(.font, at: index, effectiveRange: nil) as! NSFont
            let after = final.attribute(.font, at: index, effectiveRange: nil) as! NSFont
            #expect(abs(before.pointSize - after.pointSize) < 0.01)
        }
        #expect(text[text.range(of: "链接")!].link == URL(string: "https://apple.com"))
    }

    @Test @MainActor func codeRolesSurviveNativeEditingAndDiskRoundTrip() throws {
        let source = "行内 `hello`\n```swift\nlet a = 1\n\nprint(a)\n```\n正文"
        let text = MarkdownFormatting.render(source)
        let context = EnvironmentValues().fontResolutionContext
        let native = NativeTextAttributes.native(text, context: context)
        let edited = NativeTextAttributes.rich(native)
        var note = Note(id: UUID(), text: "", createdAt: Date(), updatedAt: Date())
        note.richText = edited
        let saved = try JSONEncoder().encode(note)
        let restored = try JSONDecoder().decode(Note.self, from: saved)
        #expect(restored.text == String(edited.characters))
        let restoredNative = NativeTextAttributes.native(restored.richText, context: context)
        let restoredFont = restoredNative.attribute(.font, at: (restoredNative.string as NSString).range(of: "hello").location, effectiveRange: nil) as! NSFont
        let originalFont = native.attribute(.font, at: (native.string as NSString).range(of: "hello").location, effectiveRange: nil) as! NSFont
        #expect(abs(restoredFont.pointSize - originalFont.pointSize) < 0.01)
        #expect(restored.richText[restored.richText.range(of: "hello")!].font!.resolve(in: context).isMonospaced)
        #expect(restored.richText[restored.richText.range(of: "hello")!][CodeStyleAttribute.self] == "inline")
        let code = try #require(restored.richText[restored.richText.range(of: "let a = 1")!][CodeStyleAttribute.self])
        #expect(code.hasPrefix("block:"))
        #expect(restored.richText[restored.richText.range(of: "print(a)")!][CodeStyleAttribute.self] == code)
        #expect(restored.richText[restored.richText.range(of: "正文")!][CodeStyleAttribute.self] == nil)
        let range = (native.string as NSString).range(of: "let a = 1")
        #expect(native.attribute(.backgroundColor, at: range.location, effectiveRange: nil) == nil)
        let paragraph = native.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as! NSParagraphStyle
        #expect(paragraph.headIndent == 14)
        #expect(paragraph.lineSpacing == 3)
    }

    @Test @MainActor func legacyCodeLinesBecomeOneSurfaceWithoutChangingText() {
        var old = AttributedString("let a = 1")
        old.font = .body.monospaced()
        old.backgroundColor = .secondary.opacity(0.1)
        var second = AttributedString("print(a)")
        second.font = .body.monospaced()
        second.backgroundColor = .secondary.opacity(0.1)
        old += AttributedString("\n") + second
        let native = NativeTextAttributes.native(old, context: EnvironmentValues().fontResolutionContext)
        #expect(native.string == String(old.characters))
        let first = native.attribute(.weaveCodeStyle, at: 0, effectiveRange: nil) as? String
        let last = native.attribute(.weaveCodeStyle, at: native.length - 1, effectiveRange: nil) as? String
        #expect(first?.hasPrefix("block:") == true)
        #expect(first == last)
    }

    @Test @MainActor func paragraphsHaveReadingRhythmAndHangingIndents() {
        let native = NativeTextAttributes.native(MarkdownFormatting.render("# 标题\n正文\n- 列表\n> 引用"), context: EnvironmentValues().fontResolutionContext)
        let string = native.string as NSString
        let title = native.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as! NSParagraphStyle
        let body = native.attribute(.paragraphStyle, at: string.range(of: "正文").location, effectiveRange: nil) as! NSParagraphStyle
        let list = native.attribute(.paragraphStyle, at: string.range(of: "•").location, effectiveRange: nil) as! NSParagraphStyle
        #expect(title.paragraphSpacing > body.paragraphSpacing)
        #expect(body.lineSpacing == 6)
        #expect(list.headIndent > list.firstLineHeadIndent)
    }
}
#endif
