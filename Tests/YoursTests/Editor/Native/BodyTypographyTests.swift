import CoreText
import SwiftUI
import Testing

@testable import Yours

@MainActor
struct BodyTypographyTests {
    @Test(
        arguments: ["body", "heading:1", "heading:2", "heading:3", "heading:4", "heading:5", "heading:6", "bullet", "task", "quote"],
        [0, 1, 2, 3])
    func displayProjectionPreservesStoredFontAndEmphasis(role: String, emphasis: Int) throws {
        let context = EnvironmentValues().fontResolutionContext
        var text = AttributedString("中文 English 2026 👋")
        text[ParagraphStyleAttribute.self] = role
        text[InlineEmphasisAttribute.self] = emphasis
        text.font = DocumentTypography.font(for: role, emphasis: emphasis, context: context)
        let original = try #require(text.font).resolve(in: context).ctFont
        for _ in 0..<3 {
            let native = NativeTextAttributes.native(text, context: context)
            let display = try #require(native.attribute(.font, at: 0, effectiveRange: nil) as? PlatformFont) as CTFont
            let expectedName =
                role.hasPrefix("heading:")
                ? (emphasis & 1 != 0 ? BundledSerifFont.boldName : BundledSerifFont.semiboldName)
                : (emphasis & 1 != 0 ? BundledSerifFont.boldName : BundledSerifFont.regularName)
            #expect(CTFontCopyPostScriptName(display) as String == expectedName)
            #expect(abs(CTFontGetSize(display) - CTFontGetSize(original) * DocumentTypography.readingScale) < 0.001)
            #expect((CTFontGetMatrix(display).c != 0) == (emphasis & 2 != 0))
            text = NativeTextAttributes.rich(native)
            let restored = try #require(text.font).resolve(in: context).ctFont
            #expect(CTFontCopyPostScriptName(restored) == CTFontCopyPostScriptName(original))
            #expect(CTFontGetSymbolicTraits(restored) == CTFontGetSymbolicTraits(original))
            #expect(abs(CTFontGetSize(restored) - CTFontGetSize(original)) < 0.001)
            #expect(text[InlineEmphasisAttribute.self] == emphasis)
        }
        let note = Note(id: UUID(), text: String(text.characters), createdAt: .distantPast, updatedAt: .distantPast)
        var saved = note
        saved.richText = text
        let encoded = try JSONEncoder().encode(saved)
        let payload = String(decoding: encoded, as: UTF8.self)
        #expect(payload.contains("SourceHanSerif") == false)
        #expect(payload.contains("yours.storedFont") == false)
        let decoded = try JSONDecoder().decode(Note.self, from: encoded)
        #expect(decoded.richText[InlineEmphasisAttribute.self] == emphasis)
    }

    @Test(arguments: ["inline", "block:test"])
    func codeKeepsMonospacedFont(style: String) throws {
        let context = EnvironmentValues().fontResolutionContext
        var text = AttributedString("let value = 1")
        text.font = .body.monospaced().bold().italic()
        text[CodeStyleAttribute.self] = style
        text[ParagraphStyleAttribute.self] = style == "inline" ? "body" : "code"
        text[InlineEmphasisAttribute.self] = 3
        let native = NativeTextAttributes.native(text, context: context)
        let font = try #require(native.attribute(.font, at: 0, effectiveRange: nil) as? PlatformFont) as CTFont
        #expect(Font(font).resolve(in: context).isMonospaced)
        #expect(CTFontGetSymbolicTraits(font).contains(.traitBold))
        #expect(CTFontGetSymbolicTraits(font).contains(.traitItalic))
        let stored = NativeTextAttributes.rich(native)
        #expect(try #require(stored.font).resolve(in: context).isMonospaced)
        #expect(stored[CodeStyleAttribute.self] == style)
    }

    @Test(arguments: ["SourceHanSerifCN-Regular", "PingFangSC-Regular", "Georgia"])
    func explicitCustomFontIsNotReplaced(name: String) throws {
        let context = EnvironmentValues().fontResolutionContext
        try #require(BundledSerifFont.isRegistered)
        var text = AttributedString("自选字体 custom")
        text.font = .custom(name, fixedSize: 19)
        let original = try #require(text.font).resolve(in: context).ctFont
        let native = NativeTextAttributes.native(text, context: context)
        let restored = try #require(NativeTextAttributes.rich(native).font).resolve(in: context).ctFont
        #expect(CTFontCopyPostScriptName(restored) == CTFontCopyPostScriptName(original))
        #expect(CTFontGetSize(restored) == CTFontGetSize(original))
    }

    @Test(arguments: ["zh-Hans", "zh-Hant", "zh-HK"], [0, 1, 2, 3])
    func persistedSystemChineseFallbackUsesSerifAndKeepsOriginalFont(language: String, emphasis: Int) throws {
        let context = EnvironmentValues().fontResolutionContext
        let system = try #require(CTFontCreateUIFontForLanguage(.system, 13, language as CFString))
        let fallback = CTFontCreateForString(system, "中文" as CFString, CFRange(location: 0, length: 2))
        var text = AttributedString("正文引用列表中文")
        text.font = Font(fallback)
        text[ParagraphStyleAttribute.self] = "body"
        text[InlineEmphasisAttribute.self] = emphasis
        text[QuoteAttribute.self] = true
        let native = NativeTextAttributes.native(text, context: context)
        let display = try #require(native.attribute(.font, at: 0, effectiveRange: nil) as? PlatformFont) as CTFont
        #expect(
            CTFontCopyPostScriptName(display) as String == (emphasis & 1 != 0 ? BundledSerifFont.boldName : BundledSerifFont.regularName))
        #expect((CTFontGetMatrix(display).c != 0) == (emphasis & 2 != 0))
        let restored = NativeTextAttributes.rich(native)
        let original = try #require(restored.font).resolve(in: context).ctFont
        #expect(CTFontCopyPostScriptName(original) == CTFontCopyPostScriptName(fallback))
        #expect(restored[InlineEmphasisAttribute.self] == emphasis)
        #expect(restored[QuoteAttribute.self] == true)
    }

    @Test func tableHeaderProjectionUsesRealBoldFace() {
        let context = EnvironmentValues().fontResolutionContext
        let header = NativeTextAttributes.displayFont(Font.body.weight(.semibold).resolve(in: context).ctFont)
        let body = NativeTextAttributes.displayFont(Font.body.resolve(in: context).ctFont)
        #expect(CTFontCopyPostScriptName(header) as String == BundledSerifFont.boldName)
        #expect(CTFontCopyPostScriptName(body) as String == BundledSerifFont.regularName)
        #expect(CTFontGetSize(header) == CTFontGetSize(body))
    }
}
