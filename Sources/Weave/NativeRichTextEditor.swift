import SwiftUI
#if os(macOS)
import AppKit
typealias PlatformTextView = NSTextView
typealias PlatformFont = NSFont
#else
import UIKit
typealias PlatformTextView = UITextView
typealias PlatformFont = UIFont
#endif

enum CodeStyleAttribute: CodableAttributedStringKey {
    typealias Value = String
    static let name = "weave.codeStyle"
}

struct NoteAttributeScope: AttributeScope {
    let swiftUI: AttributeScopes.SwiftUIAttributes
    let table: TableAttribute
    let codeLanguage: CodeLanguageAttribute
    let codeStyle: CodeStyleAttribute
    let paragraphStyle: ParagraphStyleAttribute
    let quote: QuoteAttribute
    let taskState: TaskStateAttribute
    let inlineEmphasis: InlineEmphasisAttribute
}

extension NSAttributedString.Key {
    static let weaveInlineEmphasis = NSAttributedString.Key(InlineEmphasisAttribute.name)
    static let weaveTable = NSAttributedString.Key(TableAttribute.name)
    static let weaveCodeLanguage = NSAttributedString.Key(CodeLanguageAttribute.name)
    static let weaveSyntaxColor = NSAttributedString.Key("weave.syntaxColor")
    static let weaveParagraphStyle = NSAttributedString.Key(ParagraphStyleAttribute.name)
    static let weaveQuote = NSAttributedString.Key(QuoteAttribute.name)
    static let weaveQuoteColor = NSAttributedString.Key("weave.quoteColor")
    static let weaveTaskChecked = NSAttributedString.Key(TaskStateAttribute.name)
    static let weaveInlineSpacing = NSAttributedString.Key("weave.inlineSpacing")
    static let weaveCodeStyle = NSAttributedString.Key(CodeStyleAttribute.name)
}

/// Draw code surfaces behind text while retaining native selection, caret and scrolling.
final class CodeLayoutManager: NSLayoutManager, NSLayoutManagerDelegate {
    static let headerHeight = DocumentTypography.codeHeaderHeight
    #if os(macOS)
    private struct BaselineKey: Hashable {
        let fontSize: CGFloat
        let lineHeight: CGFloat
    }
    private var baselineOffsets: [BaselineKey: CGFloat] = [:]
    #endif
    #if os(macOS)
    var emptyLineHeadIndent: CGFloat = 0 {
        didSet {
            guard emptyLineHeadIndent != oldValue,
                  let container = textContainers.first else { return }
            textContainerChangedGeometry(container)
            ensureLayout(for: container)
            guard let extraContainer = extraLineFragmentTextContainer else { return }
            // Resetting the native extra fragment makes NSTextView discard the
            // stale insertion rect it caches for a completely empty document.
            // The typesetter has already applied the typing paragraph's indent.
            super.setExtraLineFragmentRect(
                extraLineFragmentRect,
                usedRect: extraLineFragmentUsedRect,
                textContainer: extraContainer
            )
        }
    }
    #endif
    var hoveredTaskMarker: Int? {
        didSet {
            guard hoveredTaskMarker != oldValue else { return }
            if let oldValue { invalidateDisplay(forCharacterRange: NSRange(location: oldValue, length: 1)) }
            if let hoveredTaskMarker { invalidateDisplay(forCharacterRange: NSRange(location: hoveredTaskMarker, length: 1)) }
        }
    }

    func codeBackgroundRect(forGlyphRange glyphs: NSRange, in container: NSTextContainer) -> CGRect {
        var bounds = CGRect.null
        enumerateLineFragments(forGlyphRange: glyphs) { fragment, used, _, lineGlyphs, _ in
            var surface = used
            #if os(macOS)
            surface.size.height += self.interLineSpacing(for: self.characterRange(forGlyphRange: lineGlyphs, actualGlyphRange: nil))
            if lineGlyphs.location == glyphs.location {
                surface.size.height += surface.minY - fragment.minY
                surface.origin.y = fragment.minY
            }
            #endif
            bounds = bounds.union(surface)
        }
        guard !bounds.isNull else { return .zero }
        if let storage = textStorage, storage.length > 0,
           NSMaxRange(characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)) == storage.length,
           storage.string.hasSuffix("\n"),
           (storage.attribute(.weaveCodeStyle, at: storage.length - 1, effectiveRange: nil) as? String)?.hasPrefix("block:") == true,
           let paragraph = storage.attribute(.paragraphStyle, at: storage.length - 1, effectiveRange: nil) as? NSParagraphStyle {
            // An open code paragraph belongs to the surface even when the caret leaves it.
            // Do not use extraLineFragmentRect: its metrics depend on current typing attributes.
            bounds.size.height += paragraph.minimumLineHeight + paragraph.lineSpacing
        }
        let quoteInset: CGFloat
        if let storage = textStorage,
           storage.attribute(.weaveQuote, at: characterRange(forGlyphRange: glyphs, actualGlyphRange: nil).location, effectiveRange: nil) as? Bool == true {
            quoteInset = DocumentTypography.quoteIndent
        } else {
            quoteInset = 0
        }
        bounds.origin.x = container.lineFragmentPadding + quoteInset
        bounds.size.width = max(0, container.size.width - 2 * container.lineFragmentPadding - quoteInset)
        var surface = bounds.insetBy(dx: 0, dy: -8)
        if let storage = textStorage, glyphs.length > 0 {
            let source = storage.string as NSString
            let characters = characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
            let first = source.paragraphRange(for: NSRange(location: characters.location, length: 0))
            let last = source.paragraphRange(for: NSRange(location: NSMaxRange(characters) - 1, length: 0))
            func isCodeParagraph(at index: Int) -> Bool {
                let paragraph = source.paragraphRange(for: NSRange(location: index, length: 0))
                return (storage.attribute(.weaveCodeStyle, at: paragraph.location, effectiveRange: nil) as? String)?.hasPrefix("block:") == true
            }
            // Separate code ranges may touch. Their translucent padding must
            // never overlap, even when an empty range reuses an earlier block ID.
            if first.location > 0, isCodeParagraph(at: first.location - 1) {
                let top = lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil).minY
                surface.size.height -= max(0, top - surface.minY)
                surface.origin.y = max(surface.minY, top)
            }
            if NSMaxRange(last) < storage.length, isCodeParagraph(at: NSMaxRange(last)) {
                let bottom = lineFragmentRect(forGlyphAt: NSMaxRange(glyphs) - 1, effectiveRange: nil).maxY
                surface.size.height = min(surface.maxY, bottom) - surface.minY
            }
        }
        return surface
    }
    override init() {
        super.init()
        delegate = self
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        delegate = self
    }

    #if os(macOS)
    private func stableBaselineOffset(fontSize: CGFloat, lineHeight: CGFloat) -> CGFloat {
        let key = BaselineKey(fontSize: fontSize, lineHeight: lineHeight)
        if let cached = baselineOffsets[key] { return cached }
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = lineHeight
        style.maximumLineHeight = lineHeight
        let canonicalFont = CTFontCreateUIFontForLanguage(.system, fontSize, nil)
            ?? NSFont.systemFont(ofSize: fontSize) as CTFont
        let attributes: [NSAttributedString.Key: Any] = [
            // Use the concrete SF font behind SwiftUI's body role. The dynamic
            // `.AppleSystemUIFont` placeholder has different fractional leading.
            .font: canonicalFont as NSFont,
            .paragraphStyle: style
        ]
        let storage = NSTextStorage(string: "A", attributes: attributes)
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: 100, height: 100))
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        layout.ensureLayout(for: container)
        let offset = layout.location(forGlyphAt: 0).y
        baselineOffsets[key] = offset
        return offset
    }
    #endif

    func quoteBarRect(forGlyphRange glyphs: NSRange, in container: NSTextContainer) -> CGRect {
        guard glyphs.length > 0, let storage = textStorage else { return .zero }
        var bounds = CGRect.null
        enumerateLineFragments(forGlyphRange: glyphs) { fragment, _, _, lineGlyphs, _ in
            let visible = NSIntersectionRange(glyphs, lineGlyphs)
            guard visible.length > 0 else { return }
            let characters = self.characterRange(forGlyphRange: visible, actualGlyphRange: nil)
            let style = storage.attribute(.paragraphStyle, at: characters.location, effectiveRange: nil) as? NSParagraphStyle
            let font = storage.attribute(.font, at: characters.location, effectiveRange: nil) as? PlatformFont
            let fixedHeight = style?.maximumLineHeight ?? 0
            let height = fixedHeight > 0
                ? fixedHeight
                : font.map(NativeTextAttributes.stableLineHeight) ?? fragment.height
            bounds = bounds.union(CGRect(x: fragment.minX, y: fragment.minY, width: fragment.width, height: height))
        }
        guard !bounds.isNull else { return .zero }
        let characters = characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        let fontSize = characters.location < storage.length
            ? (storage.attribute(.font, at: characters.location, effectiveRange: nil) as? PlatformFont)?.pointSize ?? DocumentTypography.bodySize
            : DocumentTypography.bodySize
        // Keep the bar airy inside a quote, but stop it at the final quote
        // fragment once the following paragraph has returned to body style.
        // Otherwise its overshoot visually collides with the body caret.
        let rangeEnd = NSMaxRange(characters)
        let endsAtOpenQuote = rangeEnd == storage.length && !storage.string.hasSuffix("\n")
        let continuesQuote = rangeEnd < storage.length
            && storage.attribute(.weaveQuote, at: rangeEnd, effectiveRange: nil) as? Bool == true
        return quoteBarRect(
            forLineBounds: bounds,
            fontSize: fontSize,
            extendsBelow: endsAtOpenQuote || continuesQuote,
            in: container
        )
    }

    private func quoteBarRect(forLineBounds bounds: CGRect, fontSize: CGFloat,
                              extendsBelow: Bool, in container: NSTextContainer) -> CGRect {
        let overshoot = fontSize * DocumentTypography.quoteBarVerticalOvershootRatio
        let opticalRise = fontSize * DocumentTypography.quoteBarOpticalRiseRatio
        let bottomOvershoot = extendsBelow
            ? overshoot
            : fontSize * DocumentTypography.quoteBarTerminalBottomOvershootRatio
        return CGRect(
            x: container.lineFragmentPadding,
            y: bounds.minY - overshoot - opticalRise,
            width: 2,
            height: bounds.height + overshoot + bottomOvershoot
        )
    }

    func emptyQuoteBarRect(at insertion: Int = 0, font: PlatformFont, in container: NSTextContainer) -> CGRect {
        let fragment: CGRect
        if let storage = textStorage, storage.length > 0, insertion < storage.length {
            let glyph = glyphIndexForCharacter(at: insertion)
            fragment = lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        } else {
            fragment = extraLineFragmentRect
        }
        let lineHeight = NativeTextAttributes.stableLineHeight(for: font)
        let fontSize = font.pointSize
        let storageLength = textStorage?.length ?? 0
        let continuesQuote = insertion < storageLength
            && textStorage?.attribute(.weaveQuote, at: insertion, effectiveRange: nil) as? Bool == true
        return quoteBarRect(
            forLineBounds: CGRect(x: fragment.minX, y: fragment.minY, width: fragment.width, height: lineHeight),
            fontSize: fontSize,
            // An empty quote at the document end is still open. In the middle of
            // a document, use the same shorter terminal edge as a filled quote.
            extendsBelow: insertion >= storageLength || continuesQuote,
            in: container
        )
    }

    func layoutManager(_ layoutManager: NSLayoutManager, shouldSetLineFragmentRect lineFragmentRect: UnsafeMutablePointer<CGRect>,
                       lineFragmentUsedRect: UnsafeMutablePointer<CGRect>, baselineOffset: UnsafeMutablePointer<CGFloat>,
                       in textContainer: NSTextContainer, forGlyphRange glyphRange: NSRange) -> Bool {
        guard let storage = textStorage, glyphRange.length > 0 else { return false }
        let character = characterIndexForGlyph(at: glyphRange.location)
        guard character < storage.length else { return false }
        #if os(macOS)
        // Keep a small share below the glyphs so native selection and caret do
        // not hug descenders, while most reading spacing stays outside input geometry.
        let characters = characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        let spacing = interLineSpacing(for: characters)
        let paragraph = storage.attribute(.paragraphStyle, at: character, effectiveRange: nil) as? NSParagraphStyle
        let codeStyle = storage.attribute(.weaveCodeStyle, at: character, effectiveRange: nil) as? String
        let hasAttachment = storage.attribute(.attachment, at: character, effectiveRange: nil) != nil
        let font = storage.attribute(.font, at: character, effectiveRange: nil) as? PlatformFont
        let stableContentHeight: CGFloat?
        if let maximum = paragraph?.maximumLineHeight, maximum > 0 {
            stableContentHeight = maximum
        } else if !hasAttachment, codeStyle?.hasPrefix("block:") != true, let font {
            // AppKit can temporarily drop the paragraph's maximum line height
            // while installing IME marked text. Keep normal prose on the same
            // mixed-script line box instead of falling back to the current
            // Latin or CJK glyph bounds.
            stableContentHeight = NativeTextAttributes.stableLineHeight(for: font)
        } else {
            stableContentHeight = nil
        }
        if let stableContentHeight {
            let last = (storage.string as NSString).character(at: NSMaxRange(characters) - 1)
            let paragraphSpacing = last == 10 || last == 0x2029 ? paragraph?.paragraphSpacing ?? 0 : 0
            lineFragmentRect.pointee.size.height = stableContentHeight + spacing + paragraphSpacing
            lineFragmentUsedRect.pointee.size.height = stableContentHeight + spacing * DocumentTypography.selectionLineSpacingShare
            if let font {
                let baseFontSize = codeStyle == "inline"
                    ? font.pointSize / DocumentTypography.inlineCodeScale
                    : font.pointSize
                // TextKit substitutes PingFang while composing or committing
                // CJK text. Its leading differs from SF by about half a point,
                // so normalize the baseline as well as the line box.
                baselineOffset.pointee = stableBaselineOffset(
                    fontSize: baseFontSize,
                    lineHeight: stableContentHeight
                )
            }
        } else {
            lineFragmentUsedRect.pointee.size.height -= spacing * (1 - DocumentTypography.selectionLineSpacingShare)
        }
        #endif
        var range = NSRange()
        guard let id = storage.attribute(.weaveCodeStyle, at: character, longestEffectiveRange: &range, in: NSRange(location: 0, length: storage.length)) as? String,
              id.hasPrefix("block:"), character == range.location else { return true }
        // TextKit ignores paragraphSpacingBefore at the start of a document.
        // Reserve the header in the first code line's layout, without inserting text.
        lineFragmentRect.pointee.size.height += Self.headerHeight
        #if os(macOS)
        lineFragmentUsedRect.pointee.origin.y += Self.headerHeight
        #else
        lineFragmentUsedRect.pointee.size.height += Self.headerHeight
        #endif
        baselineOffset.pointee += Self.headerHeight
        return true
    }

    #if os(macOS)
    private func interLineSpacing(for characters: NSRange) -> CGFloat {
        guard let storage = textStorage, characters.length > 0,
              let paragraph = storage.attribute(.paragraphStyle, at: characters.location, effectiveRange: nil) as? NSParagraphStyle else { return 0 }
        let last = (storage.string as NSString).character(at: NSMaxRange(characters) - 1)
        return NSMaxRange(characters) < storage.length || last == 10 || last == 0x2028 || last == 0x2029
            ? paragraph.lineSpacing : 0
    }
    #endif

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        guard let storage = textStorage else {
            super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
            return
        }
        storage.enumerateAttribute(.weaveCodeStyle, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard let style = value as? String else { return }
            let glyphs = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard style.hasPrefix("block:") || NSIntersectionRange(glyphs, glyphsToShow).length > 0,
                  let container = self.textContainer(forGlyphAt: glyphs.location, effectiveRange: nil) else { return }
            #if os(macOS)
            NSColor.labelColor.withAlphaComponent(0.06).setFill()
            #else
            UIColor.label.withAlphaComponent(0.06).setFill()
            #endif
            if style.hasPrefix("block:") {
                let rect = self.codeBackgroundRect(forGlyphRange: glyphs, in: container).offsetBy(dx: origin.x, dy: origin.y)
                self.fill(rect, radius: 8)
            } else {
                #if os(macOS)
                let dark = NSAppearance.currentDrawing().bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                NSColor.labelColor.withAlphaComponent(dark ? 0.12 : 0.065).setFill()
                #else
                UIColor.label.withAlphaComponent(UITraitCollection.current.userInterfaceStyle == .dark ? 0.12 : 0.065).setFill()
                #endif
                for rect in self.inlineCodeBackgroundRects(forGlyphRange: glyphs, in: container) {
                    self.fill(rect.offsetBy(dx: origin.x, dy: origin.y), radius: self.inlineCodeFontSize(forGlyphRange: glyphs) * DocumentTypography.inlineCodeRadiusRatio)
                }
            }
        }
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
    }

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage, storage.length > 0 else { return }
        #if os(macOS)
        if let textView = textContainers.first?.textView {
            let selected = MainActor.assumeIsolated { textView.selectedRange() }
            if selected.length > 0 {
                NSColor.textBackgroundColor.setFill()
                for rect in selectionCleanupRects(for: selected) {
                    fill(rect.offsetBy(dx: origin.x, dy: origin.y), radius: 0)
                }
            }
        }
        #endif
        #if !os(macOS)
        drawQuoteBars(forGlyphRange: glyphsToShow, at: origin)
        #endif
        let visible = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        let source = storage.string as NSString
        var location = source.paragraphRange(for: NSRange(location: visible.location, length: 0)).location
        let end = min(storage.length, NSMaxRange(visible))
        while location < end {
            let paragraph = source.paragraphRange(for: NSRange(location: location, length: 0))
            if let marker = taskMarkerIndex(in: paragraph),
               let rect = taskMarkerRect(at: marker)?.offsetBy(dx: origin.x, dy: origin.y) {
                drawTaskMarker(
                    checked: storage.attribute(.weaveTaskChecked, at: marker, effectiveRange: nil) as? Bool ?? false,
                    hovered: hoveredTaskMarker == marker,
                    in: rect
                )
            }
            let next = NSMaxRange(paragraph)
            if next <= location { break }
            location = next
        }
    }

    #if os(macOS)
    func selectionCleanupRects(for selection: NSRange) -> [CGRect] {
        guard let storage = textStorage, selection.length > 0, storage.length > 0 else { return [] }
        let source = storage.string as NSString
        var rects: [CGRect] = []
        var location = source.paragraphRange(for: NSRange(location: min(selection.location, storage.length - 1), length: 0)).location
        let end = min(storage.length, NSMaxRange(selection))
        while location < end {
            let paragraph = source.paragraphRange(for: NSRange(location: location, length: 0))
            let intersection = NSIntersectionRange(paragraph, selection)
            guard intersection.length > 0 else { break }
            let content = source.substring(with: paragraph).trimmingCharacters(in: .whitespacesAndNewlines)
            let role = storage.attribute(.weaveParagraphStyle, at: paragraph.location, effectiveRange: nil) as? String ?? "body"
            let glyphs = glyphRange(forCharacterRange: paragraph, actualCharacterRange: nil)
            if content.isEmpty, role == "body", glyphs.length > 0 {
                enumerateLineFragments(forGlyphRange: glyphs) { fragment, _, _, _, _ in
                    rects.append(fragment)
                }
            }
            let next = NSMaxRange(paragraph)
            if next <= location { break }
            location = next
        }
        return rects
    }
    #endif

    func quoteBarDrawingRects(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint,
                              trailingEmptyBar: CGRect? = nil) -> [CGRect] {
        guard let storage = textStorage else { return [] }
        var rects: [CGRect] = []
        storage.enumerateAttribute(.weaveQuote, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard value as? Bool == true else { return }
            var drawnCharacters = range
            if drawnCharacters.length > 1,
               (storage.string as NSString).substring(with: NSRange(location: NSMaxRange(drawnCharacters) - 1, length: 1)) == "\n" {
                // A paragraph's terminating newline keeps its quote semantics
                // for serialization, but its TextKit glyph range reaches into
                // the following line. The active trailing empty quote is drawn
                // separately from typing attributes below.
                drawnCharacters.length -= 1
            }
            let glyphs = self.glyphRange(forCharacterRange: drawnCharacters, actualCharacterRange: nil)
            guard NSIntersectionRange(glyphs, glyphsToShow).length > 0,
                  let container = self.textContainer(forGlyphAt: glyphs.location, effectiveRange: nil) else { return }
            rects.append(self.quoteBarRect(forGlyphRange: glyphs, in: container)
                .offsetBy(dx: origin.x, dy: origin.y))
        }
        if let trailingEmptyBar,
           storage.length > 0,
           storage.string.hasSuffix("\n"),
           storage.attribute(.weaveQuote, at: storage.length - 1, effectiveRange: nil) as? Bool == true,
           !rects.isEmpty {
            rects[rects.count - 1] = rects[rects.count - 1].union(trailingEmptyBar)
        }
        return rects
    }

    @discardableResult
    fileprivate func drawQuoteBars(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint,
                                   trailingEmptyBar: CGRect? = nil) -> Bool {
        let rects = quoteBarDrawingRects(
            forGlyphRange: glyphsToShow,
            at: origin,
            trailingEmptyBar: trailingEmptyBar
        )
        #if os(macOS)
        NSColor.labelColor.withAlphaComponent(0.22).setFill()
        #else
        UIColor.label.withAlphaComponent(0.22).setFill()
        #endif
        for rect in rects { fill(rect, radius: 1) }
        return trailingEmptyBar.map { empty in rects.contains(where: { $0.contains(empty) }) } ?? false
    }

    func taskMarkerRect(at character: Int) -> CGRect? {
        guard let storage = textStorage, character >= 0, character < storage.length,
              storage.attribute(.weaveParagraphStyle, at: character, effectiveRange: nil) as? String == "task" else { return nil }
        let reference = character
        guard let font = storage.attribute(.font, at: reference, effectiveRange: nil) as? PlatformFont else { return nil }
        let glyphs = glyphRange(forCharacterRange: NSRange(location: reference, length: 1), actualCharacterRange: nil)
        guard glyphs.length > 0,
              textContainer(forGlyphAt: glyphs.location, effectiveRange: nil) != nil else { return nil }
        let fragment = lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
        let textX = fragment.minX + location(forGlyphAt: glyphs.location).x
        let baseline = fragment.minY + self.location(forGlyphAt: glyphs.location).y
        let ascent = CTFontGetAscent(font as CTFont)
        let descent = CTFontGetDescent(font as CTFont)
        return taskMarkerRect(textX: textX, baseline: baseline, font: font, ascent: ascent, descent: descent)
    }

    #if os(macOS)
    func emptyTaskMarkerRect(at insertion: Int, font: NSFont, quoted: Bool,
                             in container: NSTextContainer) -> CGRect {
        let fragment: CGRect
        if let storage = textStorage, storage.length > 0, insertion < storage.length {
            fragment = lineFragmentRect(forGlyphAt: glyphIndexForCharacter(at: insertion), effectiveRange: nil)
        } else {
            fragment = extraLineFragmentRect
        }
        let lineHeight = NativeTextAttributes.stableLineHeight(for: font)
        let baseline = fragment.minY + stableBaselineOffset(fontSize: font.pointSize, lineHeight: lineHeight)
        let textX = fragment.minX + DocumentTypography.listIndent
            + (quoted ? DocumentTypography.quoteIndent : 0)
        return taskMarkerRect(
            textX: textX,
            baseline: baseline,
            font: font,
            ascent: CTFontGetAscent(font as CTFont),
            descent: CTFontGetDescent(font as CTFont)
        )
    }
    #endif

    private func taskMarkerRect(textX: CGFloat, baseline: CGFloat, font: PlatformFont,
                                ascent: CGFloat, descent: CGFloat) -> CGRect {
        let size = font.pointSize * DocumentTypography.taskIconScale
        let textGap = font.pointSize * DocumentTypography.taskTextGapRatio
        // Align to the font's full typographic box. Cap height biases the
        // square downward beside Chinese and mixed-script body text.
        let centerY = baseline + (descent - ascent) / 2
        return CGRect(x: textX - textGap - size, y: centerY - size / 2, width: size, height: size)
    }

    func taskMarkerCharacter(at point: CGPoint, in container: NSTextContainer) -> Int? {
        guard let storage = textStorage, storage.length > 0 else { return nil }
        let glyph = glyphIndex(for: point, in: container)
        let character = min(storage.length - 1, characterIndexForGlyph(at: min(glyph, max(0, numberOfGlyphs - 1))))
        let paragraph = (storage.string as NSString).paragraphRange(for: NSRange(location: character, length: 0))
        guard let marker = taskMarkerIndex(in: paragraph), let hitRect = taskMarkerHitRect(at: marker) else { return nil }
        return hitRect.contains(point) ? marker : nil
    }

    func taskMarkerHitRect(at character: Int) -> CGRect? {
        guard let rect = taskMarkerRect(at: character) else { return nil }
        return taskMarkerHitRect(for: rect)
    }

    func taskMarkerHitRect(for rect: CGRect) -> CGRect {
        let hitSize = max(DocumentTypography.taskIconHitSize, max(rect.width, rect.height))
        return CGRect(x: rect.midX - hitSize / 2, y: rect.midY - hitSize / 2, width: hitSize, height: hitSize)
    }

    func taskMarkerIndex(in paragraph: NSRange) -> Int? {
        guard let storage = textStorage, paragraph.location < storage.length else { return nil }
        let source = storage.string as NSString
        var marker = paragraph.location
        while marker < NSMaxRange(paragraph), source.character(at: marker) == 9 { marker += 1 }
        guard marker < storage.length,
              storage.attribute(.weaveParagraphStyle, at: marker, effectiveRange: nil) as? String == "task",
              storage.attribute(.weaveTaskChecked, at: marker, effectiveRange: nil) is Bool else { return nil }
        return marker
    }

    func taskMarkerAdjacent(to insertion: Int) -> Int? {
        guard let storage = textStorage, storage.length > 0, insertion >= 0, insertion <= storage.length else { return nil }
        let source = storage.string as NSString
        let probe = min(insertion, storage.length - 1)
        let paragraph = source.paragraphRange(for: NSRange(location: probe, length: 0))
        guard let marker = taskMarkerIndex(in: paragraph), insertion == marker else { return nil }
        return marker
    }

    func selectionAvoidingTaskMarker(_ selection: NSRange) -> NSRange {
        selection
    }

    fileprivate func drawTaskMarker(checked: Bool, hovered: Bool, in rect: CGRect) {
        let borderInset = max(0.75, rect.height * DocumentTypography.taskBorderWidthRatio / 2)
        let outlineRect = rect.insetBy(dx: borderInset, dy: borderInset)
        let cornerRadius = outlineRect.height * DocumentTypography.taskCornerRadiusRatio
        let borderWidth = max(1, rect.height * DocumentTypography.taskBorderWidthRatio)
        #if os(macOS)
        let borderColor = NSColor.secondaryLabelColor
        let accentColor = NSColor.controlAccentColor
        let outline = NSBezierPath(roundedRect: outlineRect, xRadius: cornerRadius, yRadius: cornerRadius)
        (hovered ? accentColor : borderColor).setStroke()
        outline.lineWidth = borderWidth
        outline.stroke()
        guard checked else { return }
        let sizeConfiguration = NSImage.SymbolConfiguration(
            pointSize: rect.height * DocumentTypography.taskCheckScale,
            weight: .semibold,
            scale: .large
        )
        let colorConfiguration = NSImage.SymbolConfiguration(paletteColors: [accentColor])
        let configuration = sizeConfiguration.applying(colorConfiguration)
        guard let image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)?.withSymbolConfiguration(configuration) else { return }
        let checkSize = rect.height * DocumentTypography.taskCheckScale
        let ratio = image.size.width / max(1, image.size.height)
        let horizontalOffset = rect.height * DocumentTypography.taskCheckHorizontalOffsetRatio
        let target = CGRect(x: rect.midX - checkSize * ratio / 2 + horizontalOffset, y: rect.midY - checkSize / 2, width: checkSize * ratio, height: checkSize)
        image.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        #else
        let borderColor = UIColor.secondaryLabel
        let accentColor = UIColor(Color.accentColor)
        let outline = UIBezierPath(roundedRect: outlineRect, cornerRadius: cornerRadius)
        borderColor.setStroke()
        outline.lineWidth = borderWidth
        outline.stroke()
        guard checked else { return }
        let sizeConfiguration = UIImage.SymbolConfiguration(
            pointSize: rect.height * DocumentTypography.taskCheckScale,
            weight: .semibold,
            scale: .large
        )
        let colorConfiguration = UIImage.SymbolConfiguration(paletteColors: [accentColor])
        let configuration = sizeConfiguration.applying(colorConfiguration)
        guard let image = UIImage(systemName: "checkmark", withConfiguration: configuration) else { return }
        let checkSize = rect.height * DocumentTypography.taskCheckScale
        let ratio = image.size.width / max(1, image.size.height)
        let horizontalOffset = rect.height * DocumentTypography.taskCheckHorizontalOffsetRatio
        let target = CGRect(x: rect.midX - checkSize * ratio / 2 + horizontalOffset, y: rect.midY - checkSize / 2, width: checkSize * ratio, height: checkSize)
        image.draw(in: target)
        #endif
    }

    private func inlineCodeFontSize(forGlyphRange glyphs: NSRange) -> CGFloat {
        guard let storage = textStorage else { return DocumentTypography.bodySize * DocumentTypography.inlineCodeScale }
        let characters = characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        var size: CGFloat = 0
        storage.enumerateAttribute(.font, in: characters) { value, _, _ in
            if let font = value as? PlatformFont { size = max(size, font.pointSize) }
        }
        return size > 0 ? size : DocumentTypography.bodySize * DocumentTypography.inlineCodeScale
    }

    func inlineCodeBackgroundRects(forGlyphRange glyphs: NSRange, in container: NSTextContainer) -> [CGRect] {
        guard let storage = textStorage else { return [] }
        var result: [CGRect] = []
        enumerateLineFragments(forGlyphRange: glyphs) { fragment, _, _, lineGlyphs, _ in
            let visible = NSIntersectionRange(glyphs, lineGlyphs)
            guard visible.length > 0 else { return }
            let characters = self.characterRange(forGlyphRange: visible, actualGlyphRange: nil)
            let text = storage.attributedSubstring(from: characters)
            let size = self.inlineCodeFontSize(forGlyphRange: visible)
            let ink = CTLineGetBoundsWithOptions(CTLineCreateWithAttributedString(text), .useGlyphPathBounds)
            var above = max(0, ink.maxY)
            var below = max(0, -ink.minY)
            text.enumerateAttribute(.font, in: NSRange(location: 0, length: text.length)) { value, _, _ in
                guard let font = value as? PlatformFont else { return }
                // Cap height excludes the font's unused ascender space. Reserve
                // descenders consistently, and let CJK/emoji expand the surface.
                above = max(above, CTFontGetCapHeight(font as CTFont))
                below = max(below, CTFontGetDescent(font as CTFont))
            }
            let baseline = fragment.minY + self.location(forGlyphAt: visible.location).y
            self.enumerateEnclosingRects(forGlyphRange: visible, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: container) { rect, _ in
                var background = CGRect(x: rect.minX, y: baseline - above - size * DocumentTypography.inlineCodeBackgroundRiseRatio, width: rect.width, height: above + below)
                let last = (storage.string as NSString).rangeOfComposedCharacterSequence(at: NSMaxRange(characters) - 1).location
                if storage.attribute(.weaveInlineSpacing, at: last, effectiveRange: nil) != nil {
                    let original = storage.attribute(.weaveInlineSpacing, at: last, effectiveRange: nil) as? CGFloat ?? 0
                    let current = storage.attribute(.kern, at: last, effectiveRange: nil) as? CGFloat ?? original
                    background.size.width = max(0, background.width - (current - original))
                }
                result.append(background.insetBy(dx: -size * DocumentTypography.inlineCodePaddingRatio, dy: -size * DocumentTypography.inlineCodeVerticalPaddingRatio))
            }
        }
        return result
    }

    fileprivate func fill(_ rect: CGRect, radius: CGFloat) {
        #if os(macOS)
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        #else
        UIBezierPath(roundedRect: rect, cornerRadius: radius).fill()
        #endif
    }
}

/// Keeps the persisted SwiftUI attributes separate from the platform input system.
enum NativeTextAttributes {
    // Display scaling is reversible; stored font sizes remain independent of the reading layout.
    static let readingScale = DocumentTypography.readingScale

    static func displayFont(_ font: CTFont) -> CTFont {
        CTFontCreateCopyWithAttributes(font, CTFontGetSize(font) * readingScale, nil, nil)
    }

    static func storedFont(_ font: CTFont) -> CTFont {
        CTFontCreateCopyWithAttributes(font, CTFontGetSize(font) / readingScale, nil, nil)
    }

    static func stableLineHeight(for font: PlatformFont) -> CGFloat {
        let sample = NSAttributedString(string: "Ag\u{4E2D}\u{6587}", attributes: [.font: font])
        let line = CTLineCreateWithAttributedString(sample)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        return ceil(max(font.pointSize * DocumentTypography.lineHeightRatio, ascent + descent + leading)) + 1
    }

    private static func layoutInlineCode(_ text: NSMutableAttributedString) {
        let whole = NSRange(location: 0, length: text.length)
        text.enumerateAttribute(.weaveInlineSpacing, in: whole) { previous, range, _ in
            guard let previous = previous as? CGFloat else { return }
            if previous == 0 { text.removeAttribute(.kern, range: range) }
            else { text.addAttribute(.kern, value: previous, range: range) }
        }
        text.removeAttribute(.weaveInlineSpacing, range: whole)
        let source = text.string as NSString
        func addGap(at index: Int, amount: CGFloat) {
            guard amount > 0 else { return }
            let range = source.rangeOfComposedCharacterSequence(at: index)
            let previous = text.attribute(.kern, at: index, effectiveRange: nil) as? CGFloat ?? 0
            text.addAttributes([.kern: previous + amount, .weaveInlineSpacing: previous], range: range)
        }
        func isInline(at index: Int) -> Bool {
            index >= 0 && index < text.length && text.attribute(.weaveCodeStyle, at: index, effectiveRange: nil) as? String == "inline"
        }
        func gap(beside range: NSRange, size: CGFloat) -> CGFloat {
            let character = source.substring(with: range)
            if character.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return 0 }
            return size * (DocumentTypography.inlineCodePaddingRatio + DocumentTypography.inlineCodeMarginRatio)
        }
        func spaceWidth(at index: Int) -> CGFloat {
            CGFloat(CTLineGetTypographicBounds(CTLineCreateWithAttributedString(text.attributedSubstring(from: NSRange(location: index, length: 1))), nil, nil, nil))
        }
        text.enumerateAttribute(.weaveCodeStyle, in: whole) { value, range, _ in
            guard value as? String == "inline", range.length > 0 else { return }
            let size = (text.attribute(.font, at: range.location, effectiveRange: nil) as? PlatformFont)?.pointSize ?? DocumentTypography.bodySize * DocumentTypography.inlineCodeScale
            if range.location > 0 {
                let previous = source.rangeOfComposedCharacterSequence(at: range.location - 1)
                if source.substring(with: previous) == " " {
                    // Count the existing space toward the visual gap. Multiple
                    // spaces, tabs and line breaks retain their authored spacing.
                    if previous.location > 0 {
                        let neighbor = source.rangeOfComposedCharacterSequence(at: previous.location - 1)
                        let neighborSize = (text.attribute(.font, at: neighbor.location, effectiveRange: nil) as? PlatformFont)?.pointSize ?? size
                        let target = isInline(at: neighbor.location)
                            ? (size + neighborSize) * (DocumentTypography.inlineCodePaddingRatio + DocumentTypography.inlineCodeMarginRatio)
                            : gap(beside: neighbor, size: size)
                        addGap(at: previous.location, amount: max(0, target - spaceWidth(at: previous.location)))
                    }
                } else { addGap(at: previous.location, amount: gap(beside: previous, size: size)) }
            }
            let end = NSMaxRange(range)
            if end < text.length {
                let next = source.rangeOfComposedCharacterSequence(at: end)
                let last = source.rangeOfComposedCharacterSequence(at: end - 1).location
                if source.substring(with: next) == " " {
                    if end + 1 < text.length, !isInline(at: end + 1) {
                        let neighbor = source.rangeOfComposedCharacterSequence(at: end + 1)
                        addGap(at: last, amount: max(0, gap(beside: neighbor, size: size) - spaceWidth(at: end)))
                    }
                } else { addGap(at: last, amount: gap(beside: next, size: size)) }
            }
        }
    }

    static func layoutParagraphs(_ text: NSMutableAttributedString) {
        layoutInlineCode(text)
        let whole = NSRange(location: 0, length: text.length)
        text.enumerateAttribute(.weaveQuoteColor, in: whole) { value, range, _ in
            guard value != nil else { return }
            #if os(macOS)
            text.addAttribute(.foregroundColor, value: NSColor.textColor, range: range)
            #else
            text.addAttribute(.foregroundColor, value: UIColor.label, range: range)
            #endif
        }
        text.removeAttribute(.weaveQuoteColor, range: whole)
        let source = text.string as NSString
        var location = 0
        while location < source.length {
            let range = source.paragraphRange(for: NSRange(location: location, length: 0))
            let content = source.substring(with: range).trimmingCharacters(in: .newlines)
            var font = text.attribute(.font, at: location, effectiveRange: nil) as? PlatformFont
            if text.attribute(.weaveCodeStyle, at: location, effectiveRange: nil) as? String == "inline", let inlineFont = font {
                font = CTFontCreateCopyWithAttributes(inlineFont as CTFont, inlineFont.pointSize / DocumentTypography.inlineCodeScale, nil, nil) as PlatformFont
            }
            let paragraph = NSMutableParagraphStyle()
            if let font {
                // Build one line box from both Latin and CJK metrics before
                // fallback glyphs arrive. The extra point keeps both scripts clear.
                let stableLineHeight = stableLineHeight(for: font)
                paragraph.minimumLineHeight = stableLineHeight
                // TextKit otherwise changes a Latin line by about half a point as
                // soon as a CJK fallback glyph appears, which visibly moves the
                // caret and following content while typing. Attachments stay
                // unconstrained because their height belongs to their content.
                if text.attribute(.attachment, at: location, effectiveRange: nil) == nil {
                    paragraph.maximumLineHeight = stableLineHeight
                }
            }
            paragraph.lineSpacing = DocumentTypography.bodyLineSpacing
            paragraph.paragraphSpacing = DocumentTypography.bodyParagraphSpacing
            let role = text.attribute(.weaveParagraphStyle, at: location, effectiveRange: nil) as? String ?? "body"
            let quoted = text.attribute(.weaveQuote, at: location, effectiveRange: nil) as? Bool == true
                || role == "quote" || content.hasPrefix("│ ")
            if let heading = DocumentTypography.heading(for: role) {
                paragraph.lineSpacing = heading.lineSpacing
                paragraph.paragraphSpacingBefore = location == 0 ? 0 : heading.before
                paragraph.paragraphSpacing = heading.after
            }
            if content.trimmingCharacters(in: .whitespaces).hasPrefix("• ") || role == "task" || content.range(of: #"^\d+\. "#, options: .regularExpression) != nil {
                paragraph.headIndent = DocumentTypography.listIndent
                paragraph.paragraphSpacing = DocumentTypography.listSpacing
            }
            if role == "task" {
                paragraph.firstLineHeadIndent = DocumentTypography.listIndent
            }
            if quoted {
                text.addAttribute(.weaveQuote, value: true, range: range)
                if content.hasPrefix("│ ") {
                    #if os(macOS)
                    text.addAttribute(.foregroundColor, value: NSColor.clear, range: NSRange(location: location, length: 1))
                    #else
                    text.addAttribute(.foregroundColor, value: UIColor.clear, range: NSRange(location: location, length: 1))
                    #endif
                    if let font {
                        let markerLine = CTLineCreateWithAttributedString(NSAttributedString(string: "│", attributes: [.font: font]))
                        let markerWidth = CGFloat(CTLineGetTypographicBounds(markerLine, nil, nil, nil))
                        let spaceLine = CTLineCreateWithAttributedString(NSAttributedString(string: " ", attributes: [.font: font]))
                        let spaceWidth = CGFloat(CTLineGetTypographicBounds(spaceLine, nil, nil, nil))
                        text.addAttribute(.kern, value: -markerWidth, range: NSRange(location: location, length: 1))
                        text.addAttribute(.kern, value: -spaceWidth, range: NSRange(location: location + 1, length: 1))
                    }
                }
            }
            if let code = text.attribute(.weaveCodeStyle, at: location, effectiveRange: nil) as? String, code.hasPrefix("block:") {
                let previous = location > 0 ? text.attribute(.weaveCodeStyle, at: location - 1, effectiveRange: nil) as? String : nil
                let next = NSMaxRange(range) < text.length ? text.attribute(.weaveCodeStyle, at: NSMaxRange(range), effectiveRange: nil) as? String : nil
                paragraph.maximumLineHeight = 0
                paragraph.lineSpacing = DocumentTypography.codeLineSpacing
                paragraph.firstLineHeadIndent = DocumentTypography.codeInset
                paragraph.headIndent = DocumentTypography.codeInset
                paragraph.tailIndent = -DocumentTypography.codeInset
                paragraph.paragraphSpacingBefore = previous == code ? 0 : DocumentTypography.codeBefore
                paragraph.paragraphSpacing = next == code ? 0 : DocumentTypography.codeAfter
            }
            if quoted {
                let structured = role == "task" || role == "bullet" || role == "numbered" || role == "code"
                    || MarkdownShortcut.listPrefix(content) != nil
                paragraph.firstLineHeadIndent += DocumentTypography.quoteIndent
                paragraph.headIndent += structured ? DocumentTypography.quoteIndent : DocumentTypography.quoteContinuationIndent
                if !structured { paragraph.paragraphSpacing = DocumentTypography.quoteSpacing }
                text.enumerateAttribute(.foregroundColor, in: range) { value, colorRange, _ in
                    #if os(macOS)
                    guard value == nil || value as? NSColor == NSColor.textColor else { return }
                    text.addAttributes([.foregroundColor: NSColor.secondaryLabelColor, .weaveQuoteColor: true], range: colorRange)
                    #else
                    guard value == nil || value as? UIColor == UIColor.label else { return }
                    text.addAttributes([.foregroundColor: UIColor.secondaryLabel, .weaveQuoteColor: true], range: colorRange)
                    #endif
                }
            }
            let level = MarkdownShortcut.listPrefix(content) == nil && role != "task" ? 0 : content.prefix(while: { $0 == "\t" }).count
            paragraph.headIndent += CGFloat(level) * DocumentTypography.listIndent
            if text.attribute(.weaveCodeStyle, at: location, effectiveRange: nil) as? String == "inline",
               let inlineFont = text.attribute(.font, at: location, effectiveRange: nil) as? PlatformFont {
                // A leading inline span has no preceding character to carry its
                // inset. Reserve it through native paragraph layout instead.
                paragraph.firstLineHeadIndent += inlineFont.pointSize * (DocumentTypography.inlineCodePaddingRatio + DocumentTypography.inlineCodeMarginRatio)
            }
            paragraph.tabStops = (1...12).map { NSTextTab(textAlignment: .left, location: CGFloat($0) * DocumentTypography.listIndent) }
            // Paragraph metrics follow their semantic role, never whether the
            // line or its neighbours currently contain text. Typing the first
            // character must not introduce margins or move subsequent content.
            text.addAttribute(.paragraphStyle, value: paragraph, range: range)
            location = NSMaxRange(range)
        }
    }

    @MainActor static func native(_ text: AttributedString, context: Font.Context) -> NSAttributedString {
        let result = NSMutableAttributedString(string: String(text.characters))
        for run in text.runs {
            let range = NSRange(run.range, in: text)
            var attributes: [NSAttributedString.Key: Any] = [:]
            let emphasis = DocumentTypography.emphasis(in: run.attributes, context: context)
            let role = run[ParagraphStyleAttribute.self] ?? "body"
            let font = role.hasPrefix("heading:") || run[CodeStyleAttribute.self] == "inline"
                ? DocumentTypography.font(for: role, emphasis: emphasis, inlineCode: run[CodeStyleAttribute.self] == "inline", context: context)
                : run.font ?? .body
            attributes[.font] = displayFont(font.resolve(in: context).ctFont)
            attributes[.weaveInlineEmphasis] = emphasis
            if let style = run[ParagraphStyleAttribute.self] { attributes[.weaveParagraphStyle] = style }
            if run[QuoteAttribute.self] == true { attributes[.weaveQuote] = true }
            if let checked = run[TaskStateAttribute.self] { attributes[.weaveTaskChecked] = checked }
            if let style = run[CodeStyleAttribute.self] {
                attributes[.weaveCodeStyle] = style
            } else if (run.font ?? .body).resolve(in: context).isMonospaced {
                // Compatibility with documents saved before code roles were persisted.
                attributes[.weaveCodeStyle] = run.backgroundColor == Color.secondary.opacity(0.1) ? "legacy-block" : "inline"
            }
            if let table = run[TableAttribute.self], String(text[run.range].characters) == "\u{FFFC}" {
                attributes[.weaveTable] = try? JSONEncoder().encode(table)
                attributes[.attachment] = TableTextAttachment(table: table)
            }
            if let language = run[CodeLanguageAttribute.self] { attributes[.weaveCodeLanguage] = language }
            if let link = run.link { attributes[.link] = link }
            if run.underlineStyle != nil { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            if run.strikethroughStyle != nil { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            #if os(macOS)
            if run[QuoteAttribute.self] == true, run.foregroundColor == nil {
                attributes[.foregroundColor] = NSColor.secondaryLabelColor
                attributes[.weaveQuoteColor] = true
            } else {
                attributes[.foregroundColor] = run.foregroundColor.map(NSColor.init) ?? NSColor.textColor
            }
            if let color = run.backgroundColor { attributes[.backgroundColor] = NSColor(color) }
            #else
            if run[QuoteAttribute.self] == true, run.foregroundColor == nil {
                attributes[.foregroundColor] = UIColor.secondaryLabel
                attributes[.weaveQuoteColor] = true
            } else {
                attributes[.foregroundColor] = run.foregroundColor.map(UIColor.init) ?? UIColor.label
            }
            if let color = run.backgroundColor { attributes[.backgroundColor] = UIColor(color) }
            #endif
            if attributes[.weaveCodeStyle] != nil { attributes.removeValue(forKey: .backgroundColor) }
            result.setAttributes(attributes, range: range)
        }
        // Old fenced code stored only per-line fonts/backgrounds. Rejoin adjacent code paragraphs.
        let source = result.string as NSString
        var location = 0
        var blockStart: Int?
        while location < result.length {
            let paragraph = source.paragraphRange(for: NSRange(location: location, length: 0))
            let content = source.substring(with: paragraph).trimmingCharacters(in: .newlines)
            let role = result.attribute(.weaveCodeStyle, at: location, effectiveRange: nil) as? String
            if role == "legacy-block", !content.isEmpty {
                if blockStart == nil { blockStart = location }
                result.addAttribute(.weaveCodeStyle, value: "block:legacy-\(blockStart!)", range: paragraph)
            } else { blockStart = nil }
            location = NSMaxRange(paragraph)
        }
        layoutParagraphs(result)
        highlightCode(result)
        return result
    }

    static func highlightCode(_ text: NSMutableAttributedString) {
        let whole = NSRange(location: 0, length: text.length)
        #if os(macOS)
        let base = NSColor.textColor
        let inlineColor = NSColor.textColor
        #else
        let base = UIColor.label
        let inlineColor = UIColor.label
        #endif
        text.enumerateAttribute(.weaveSyntaxColor, in: whole) { marker, range, _ in
            if marker != nil { text.addAttribute(.foregroundColor, value: base, range: range) }
        }
        text.removeAttribute(.weaveSyntaxColor, range: whole)
        text.enumerateAttribute(.weaveCodeStyle, in: whole) { value, range, _ in
            if value as? String == "inline" {
                text.enumerateAttribute(.foregroundColor, in: range) { color, span, _ in
                    #if os(macOS)
                    let isDefault = color as? NSColor == base
                    #else
                    let isDefault = color as? UIColor == base
                    #endif
                    if isDefault {
                        text.addAttributes([.foregroundColor: inlineColor, .weaveSyntaxColor: true], range: span)
                    }
                }
            }
            guard let id = value as? String, id.hasPrefix("block:") else { return }
            let language = text.attribute(.weaveCodeLanguage, at: range.location, effectiveRange: nil) as? String ?? ""
            let literal = (text.string as NSString).substring(with: range)
            for token in CodeBlockEditing.tokens(source: literal, language: language) {
                #if os(macOS)
                let color: NSColor
                #else
                let color: UIColor
                #endif
                switch token.kind {
                case .keyword: color = .systemPurple
                case .string: color = .systemBrown
                case .number: color = .systemBlue
                case .comment: color = .systemGray
                }
                text.addAttributes([.foregroundColor: color, .weaveSyntaxColor: true],
                    range: NSRange(location: range.location + token.range.location, length: token.range.length))
            }
        }
    }

    static func rich(_ text: NSAttributedString) -> AttributedString {
        var result = AttributedString(text.string)
        text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attributes, nsRange, _ in
            guard let range = Range<AttributedString.Index>(nsRange, in: result) else { return }
            if let encoded = attributes[.weaveTable] as? Data,
               text.attributedSubstring(from: nsRange).string == "\u{FFFC}",
               let table = try? JSONDecoder().decode(TableData.self, from: encoded) {
                result[range][TableAttribute.self] = table
            }
            if let emphasis = attributes[.weaveInlineEmphasis] as? Int { result[range][InlineEmphasisAttribute.self] = emphasis }
            if let language = attributes[.weaveCodeLanguage] as? String { result[range][CodeLanguageAttribute.self] = language }
            if let style = attributes[.weaveParagraphStyle] as? String { result[range][ParagraphStyleAttribute.self] = style }
            if attributes[.weaveQuote] as? Bool == true { result[range][QuoteAttribute.self] = true }
            if let checked = attributes[.weaveTaskChecked] as? Bool { result[range][TaskStateAttribute.self] = checked }
            if let style = attributes[.weaveCodeStyle] as? String { result[range][CodeStyleAttribute.self] = style }
            if let font = attributes[.font] as? PlatformFont { result[range].font = Font(storedFont(font as CTFont)) }
            if let link = attributes[.link] as? URL { result[range].link = link }
            else if let link = attributes[.link] as? String { result[range].link = URL(string: link) }
            if let style = attributes[.underlineStyle] as? Int, style != 0 { result[range].underlineStyle = .single }
            if let style = attributes[.strikethroughStyle] as? Int, style != 0 { result[range].strikethroughStyle = .single }
            #if os(macOS)
            if let color = attributes[.foregroundColor] as? NSColor, color != .textColor, color != .clear,
               attributes[.weaveSyntaxColor] == nil, attributes[.weaveQuoteColor] == nil { result[range].foregroundColor = Color(nsColor: color) }
            if let color = attributes[.backgroundColor] as? NSColor { result[range].backgroundColor = Color(nsColor: color) }
            #else
            if let color = attributes[.foregroundColor] as? UIColor, color != .label, color != .clear,
               attributes[.weaveSyntaxColor] == nil, attributes[.weaveQuoteColor] == nil { result[range].foregroundColor = Color(uiColor: color) }
            if let color = attributes[.backgroundColor] as? UIColor { result[range].backgroundColor = Color(uiColor: color) }
            #endif
        }
        return result
    }
}

@MainActor
struct NativeRichTextEditor {
    @Binding var text: AttributedString
    @Binding var selection: AttributedTextSelection
    var focusWhenEmpty = true
    var onEditLink: () -> Void = {}
    @Environment(\.fontResolutionContext) private var fontContext

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor
    final class Coordinator: NSObject {
        var parent: NativeRichTextEditor
        private var lastValue: AttributedString
        private var lastNativeValue = NSAttributedString()
        fileprivate var isUpdating = false
        private var locallyAppliedTypingAttributes: [NSAttributedString.Key: Any]?
        private var pendingTypingAttributesAfterInlineDeletion: [NSAttributedString.Key: Any]?
        weak var textView: PlatformTextView?
        private let tables = TableOverlayController()
        private let codeHeaders = CodeHeaderOverlayController()

        init(parent: NativeRichTextEditor) {
            self.parent = parent
            lastValue = parent.text
        }

        fileprivate var storage: NSTextStorage? {
            #if os(macOS)
            textView?.textStorage
            #else
            textView?.textStorage
            #endif
        }

        private var currentSelection: NSRange {
            #if os(macOS)
            textView?.selectedRange() ?? NSRange(location: 0, length: 0)
            #else
            textView?.selectedRange ?? NSRange(location: 0, length: 0)
            #endif
        }

        private func setSelection(_ range: NSRange) {
            #if os(macOS)
            textView?.setSelectedRange(range)
            #else
            textView?.selectedRange = range
            #endif
        }

        fileprivate var hasMarkedText: Bool {
            #if os(macOS)
            textView?.hasMarkedText() ?? false
            #else
            textView?.markedTextRange != nil
            #endif
        }

        func update(_ parent: NativeRichTextEditor) {
            self.parent = parent
            guard let textView, !hasMarkedText else { return }
            isUpdating = true
            defer { isUpdating = false; refreshTables() }
            if parent.text != lastValue {
                storage?.setAttributedString(NativeTextAttributes.native(parent.text, context: parent.fontContext))
                lastValue = parent.text
            }
            var range: NSRange
            switch parent.selection.indices(in: parent.text) {
            case .insertionPoint(let index): range = NSRange(index..<index, in: parent.text)
            case .ranges(let ranges):
                guard let first = ranges.ranges.first else { return }
                range = NSRange(first, in: parent.text)
            }
            if let layout = textView.layoutManager as? CodeLayoutManager {
                range = layout.selectionAvoidingTaskMarker(range)
            }
            if NSMaxRange(range) <= (storage?.length ?? 0), range != currentSelection { setSelection(range) }
            let attributes = parent.selection.typingAttributes(in: parent.text)
            let source = (storage?.string ?? "") as NSString
            let paragraphRange = source.paragraphRange(for: NSRange(location: min(range.location, source.length), length: 0))
            let isBlank = source.substring(with: paragraphRange).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let sample = NativeTextAttributes.native(AttributedString(isBlank ? "\n" : " ", attributes: attributes), context: parent.fontContext)
            var nativeAttributes = sample.attributes(at: 0, effectiveRange: nil)
            // A synthetic space has body margins. Reuse the actual paragraph's
            // layout when restoring typing state so clicking cannot change its height.
            if let storage, paragraphRange.location < storage.length,
               storage.attribute(.weaveParagraphStyle, at: paragraphRange.location, effectiveRange: nil) as? String == nativeAttributes[.weaveParagraphStyle] as? String,
               storage.attribute(.weaveCodeStyle, at: paragraphRange.location, effectiveRange: nil) as? String == nativeAttributes[.weaveCodeStyle] as? String {
                nativeAttributes[.paragraphStyle] = storage.attribute(.paragraphStyle, at: paragraphRange.location, effectiveRange: nil)
            }
            nativeAttributes.removeValue(forKey: .attachment)
            nativeAttributes.removeValue(forKey: .weaveTable)
            let localAttributes = locallyAppliedTypingAttributes
            locallyAppliedTypingAttributes = nil
            if let localAttributes, parent.text == lastValue, range == currentSelection {
                // `text` and `selection` are separate bindings. SwiftUI can update
                // the representable after the text write but before the matching
                // selection typing state arrives. Keep the attributes from the
                // native edit for that one intermediate update.
                textView.typingAttributes = localAttributes
            } else {
                textView.typingAttributes = nativeAttributes
            }
            #if os(macOS)
            (textView as? ReadingMacTextView)?.updateEmptyQuoteBar()
            #endif
            if let storage { lastNativeValue = NSAttributedString(attributedString: storage) }
        }

        fileprivate func publish() {
            guard !isUpdating, let storage else { return }
            if !hasMarkedText {
                isUpdating = true
                NativeTextAttributes.layoutParagraphs(storage)
                NativeTextAttributes.highlightCode(storage)
                isUpdating = false
            }
            let value = NativeTextAttributes.rich(storage)
            lastValue = value
            parent.text = value
            publishSelection(in: value)
            lastNativeValue = NSAttributedString(attributedString: storage)
            refreshTables()
        }

        fileprivate func publishSelection(in value: AttributedString? = nil) {
            guard !isUpdating, !hasMarkedText, let textView else { return }
            if let layout = textView.layoutManager as? CodeLayoutManager {
                let normalized = layout.selectionAvoidingTaskMarker(currentSelection)
                if normalized != currentSelection {
                    isUpdating = true
                    setSelection(normalized)
                    isUpdating = false
                }
            }
            let text = value ?? parent.text
            guard let range = Range<AttributedString.Index>(currentSelection, in: text) else { return }
            if range.isEmpty {
                let sample = NativeTextAttributes.rich(NSAttributedString(string: " ", attributes: textView.typingAttributes))
                parent.selection = AttributedTextSelection(insertionPoint: range.lowerBound, typingAttributes: sample.runs.first?.attributes)
            } else { parent.selection = AttributedTextSelection(range: range) }
        }

        fileprivate func refreshTables() {
            guard let textView else { return }
            codeHeaders.refresh(in: textView, onLanguage: { [weak self] id, language in
                self?.changeCodeLanguage(id: id, language: language)
            })
            tables.refresh(in: textView, onChange: { [weak self] id, table in
                self?.changeTable(id: id, table: table)
            }, onExit: { [weak self] index in
                // Let SwiftUI resign the cell before restoring the document responder.
                DispatchQueue.main.async { [weak self] in self?.exitTable(at: index) }
            })
        }

        func changeCodeLanguage(id: String, language: String) {
            guard !hasMarkedText, let storage, let view = textView else { return }
            var target: NSRange?
            storage.enumerateAttribute(.weaveCodeStyle, in: NSRange(location: 0, length: storage.length)) { value, range, stop in
                if value as? String == id { target = range; stop.pointee = true }
            }
            guard let target,
                  storage.attribute(.weaveCodeLanguage, at: target.location, effectiveRange: nil) as? String != language else { return }
            registerUndo(text: NSAttributedString(attributedString: storage), selection: currentSelection, attributes: view.typingAttributes)
            let next = NSMutableAttributedString(attributedString: storage)
            next.addAttribute(.weaveCodeLanguage, value: language, range: target)
            var attributes = view.typingAttributes
            if attributes[.weaveCodeStyle] as? String == id { attributes[.weaveCodeLanguage] = language }
            apply(text: next, selection: currentSelection, attributes: attributes)
        }

        private func exitTable(at index: Int) {
            guard let view = textView, let storage else { return }
            let offset = min(index, storage.length)
            var sample = AttributedString("\n")
            sample.font = .body
            sample[ParagraphStyleAttribute.self] = "body"
            let native = NativeTextAttributes.native(sample, context: parent.fontContext)
            let attributes = native.attributes(at: 0, effectiveRange: nil)
            if offset == storage.length || (storage.string as NSString).substring(with: NSRange(location: offset, length: 1)) != "\n" {
                registerUndo(text: NSAttributedString(attributedString: storage), selection: currentSelection, attributes: view.typingAttributes)
                let next = NSMutableAttributedString(attributedString: storage)
                next.insert(native, at: offset)
                apply(text: next, selection: NSRange(location: offset + 1, length: 0), attributes: attributes)
            }
            isUpdating = true
            setSelection(NSRange(location: min(offset + 1, storage.length), length: 0))
            view.typingAttributes = attributes
            #if os(macOS)
            view.window?.makeFirstResponder(view)
            #else
            view.becomeFirstResponder()
            #endif
            isUpdating = false
            publishSelection()
        }

        func copyStructured(cut: Bool) -> Bool {
            guard !hasMarkedText, let storage, let view = textView, currentSelection.length > 0 else { return false }
            let range = currentSelection
            let selected = NativeTextAttributes.rich(storage.attributedSubstring(from: range))
            let hasTable = selected.runs.contains { $0[TableAttribute.self] != nil }
            guard hasTable || selected.runs.contains(where: { $0[CodeStyleAttribute.self]?.hasPrefix("block:") == true }) else { return false }
            guard let encoded = try? RichTextClipboard.encode(selected) else {
                #if os(macOS)
                NSSound.beep()
                #endif
                return true // Never fall back to a lossy cut of a structured block.
            }
            let plain = hasTable ? MarkdownFormatting.serialize(selected, context: parent.fontContext) : String(selected.characters)
            #if os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setData(encoded, forType: NSPasteboard.PasteboardType("app.weave.richtext"))
            NSPasteboard.general.setString(plain, forType: .string)
            #else
            UIPasteboard.general.setItems([["app.weave.richtext": encoded, "public.utf8-plain-text": plain]])
            #endif
            if cut {
                registerUndo(text: NSAttributedString(attributedString: storage), selection: range, attributes: view.typingAttributes)
                let next = NSMutableAttributedString(attributedString: storage)
                next.deleteCharacters(in: range)
                var body = AttributedString(" ")
                body.font = .body
                body[ParagraphStyleAttribute.self] = "body"
                let attributes = NativeTextAttributes.native(body, context: parent.fontContext).attributes(at: 0, effectiveRange: nil)
                apply(text: next, selection: NSRange(location: range.location, length: 0), attributes: attributes)
                view.undoManager?.setActionName("剪切")
            }
            return true
        }

        func pasteStructured() -> Bool {
            guard !hasMarkedText, let storage, let view = textView,
                  view.typingAttributes[.weaveCodeStyle] == nil else { return false }
            #if os(macOS)
            let encoded = NSPasteboard.general.data(forType: NSPasteboard.PasteboardType("app.weave.richtext"))
            #else
            let encoded = UIPasteboard.general.data(forPasteboardType: "app.weave.richtext")
            #endif
            guard let encoded, let text = try? RichTextClipboard.decode(encoded) else { return false }
            let inserted = NativeTextAttributes.native(text, context: parent.fontContext)
            let range = currentSelection
            registerUndo(text: NSAttributedString(attributedString: storage), selection: range, attributes: view.typingAttributes)
            let next = NSMutableAttributedString(attributedString: storage)
            next.replaceCharacters(in: range, with: inserted)
            var body = AttributedString(" ")
            body.font = .body
            body[ParagraphStyleAttribute.self] = "body"
            let attributes = NativeTextAttributes.native(body, context: parent.fontContext).attributes(at: 0, effectiveRange: nil)
            apply(text: next, selection: NSRange(location: range.location + inserted.length, length: 0), attributes: attributes)
            view.undoManager?.setActionName("粘贴")
            return true
        }

        func changeTable(id: UUID, table: TableData) {
            guard let storage, let view = textView else { return }
            var target: NSRange?
            storage.enumerateAttribute(.weaveTable, in: NSRange(location: 0, length: storage.length)) { value, range, stop in
                if let encoded = value as? Data, let current = try? JSONDecoder().decode(TableData.self, from: encoded), current.id == id {
                    target = range
                    stop.pointee = true
                }
            }
            guard let target, let encoded = try? JSONEncoder().encode(table),
                  storage.attribute(.weaveTable, at: target.location, effectiveRange: nil) as? Data != encoded else { return }
            registerUndo(text: NSAttributedString(attributedString: storage), selection: currentSelection, attributes: view.typingAttributes)
            isUpdating = true
            storage.addAttributes([.weaveTable: encoded, .attachment: TableTextAttachment(table: table)], range: target)
            isUpdating = false
            publish()
            view.undoManager?.setActionName("编辑表格")
        }

        func intercept(range: NSRange, replacement: String?) -> Bool {
            guard !isUpdating, !hasMarkedText, let textView, let storage, let replacement,
                  textView.undoManager?.isUndoing != true, textView.undoManager?.isRedoing != true else { return true }
            textView.typingAttributes.removeValue(forKey: .attachment)
            textView.typingAttributes.removeValue(forKey: .weaveTable)
            if range.length > 0, textView.typingAttributes[.weaveCodeStyle] == nil, let url = URL(string: replacement),
               ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil,
               !replacement.contains(where: { $0.isWhitespace }) {
                registerUndo(text: NSAttributedString(attributedString: storage), selection: currentSelection, attributes: textView.typingAttributes)
                let updated = NSMutableAttributedString(attributedString: storage)
                updated.addAttribute(.link, value: url, range: range)
                apply(text: updated, selection: range, attributes: textView.typingAttributes)
                return false
            }
            let source = storage.string as NSString
            let caret = currentSelection
            // At end-of-document, asking NSString for the paragraph at the caret
            // can resolve to its synthetic trailing paragraph. For deletion, the
            // affected character is the reliable paragraph anchor.
            let paragraphAnchor = replacement.isEmpty && range.length > 0
                ? min(range.location, source.length)
                : min(caret.location, source.length)
            let paragraph: NSRange
            if paragraphAnchor == source.length, source.length > 0,
               source.substring(with: NSRange(location: source.length - 1, length: 1)) == "\n" {
                // `NSString.paragraphRange` assigns an insertion point after a
                // trailing newline to the preceding paragraph. TextKit treats
                // that position as the document's trailing empty paragraph.
                paragraph = NSRange(location: source.length, length: 0)
            } else {
                paragraph = source.paragraphRange(for: NSRange(location: paragraphAnchor, length: 0))
            }
            let line = source.substring(with: paragraph).trimmingCharacters(in: .newlines)
            let role = textView.typingAttributes[.weaveParagraphStyle] as? String
            let code = textView.typingAttributes[.weaveCodeStyle] as? String
            let quoteAnchor = range.length > 0 && range.location < storage.length
                ? range.location
                : paragraph.location
            let quoted = textView.typingAttributes[.weaveQuote] as? Bool == true
                || role == "quote"
                || (quoteAnchor < storage.length
                    && storage.attribute(.weaveQuote, at: quoteAnchor, effectiveRange: nil) as? Bool == true)
            if quoted, replacement.isEmpty, range.length > 0,
               NSIntersectionRange(range, paragraph).length == range.length {
                let local = NSRange(location: range.location - paragraph.location, length: range.length)
                let remaining = NSMutableString(string: line)
                if NSMaxRange(local) <= remaining.length {
                    remaining.deleteCharacters(in: local)
                    if remaining.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        registerUndo(text: NSAttributedString(attributedString: storage), selection: currentSelection, attributes: textView.typingAttributes)
                        let next = NSMutableAttributedString(attributedString: storage)
                        next.deleteCharacters(in: range)
                        var attributes = textView.typingAttributes
                        attributes[.weaveQuote] = true
                        #if os(macOS)
                        attributes[.foregroundColor] = NSColor.secondaryLabelColor
                        #else
                        attributes[.foregroundColor] = UIColor.secondaryLabel
                        #endif
                        attributes[.weaveQuoteColor] = true
                        apply(text: next, selection: NSRange(location: range.location, length: 0), attributes: attributes)
                        return false
                    }
                }
            }
            if code?.hasPrefix("block:") == true, replacement == "\t" || replacement == "\u{19}" {
                var value = NativeTextAttributes.rich(storage)
                guard let selected = Range<AttributedString.Index>(caret, in: value) else { return true }
                var selection = selected.isEmpty ? AttributedTextSelection(insertionPoint: selected.lowerBound) : AttributedTextSelection(range: selected)
                if CodeBlockEditing.indent(in: &value, selection: &selection, outdent: replacement == "\u{19}") {
                    registerUndo(text: NSAttributedString(attributedString: storage), selection: caret, attributes: textView.typingAttributes)
                    let after: NSRange
                    switch selection.indices(in: value) {
                    case .insertionPoint(let point): after = NSRange(point..<point, in: value)
                    case .ranges(let ranges): after = ranges.ranges.first.map { NSRange($0, in: value) } ?? caret
                    }
                    apply(text: NativeTextAttributes.native(value, context: parent.fontContext), selection: after, attributes: textView.typingAttributes)
                    textView.undoManager?.setActionName("代码缩进")
                    return false
                }
                // An empty newly-created block only has typing attributes.
                if replacement == "\t", caret.length == 0 {
                    registerUndo(text: NSAttributedString(attributedString: storage), selection: caret, attributes: textView.typingAttributes)
                    let next = NSMutableAttributedString(attributedString: storage)
                    next.replaceCharacters(in: range, with: NSAttributedString(string: "    ", attributes: textView.typingAttributes))
                    apply(text: next, selection: NSRange(location: range.location + 4, length: 0), attributes: textView.typingAttributes)
                }
                return false
            }
            if code?.hasPrefix("block:") == true, replacement == "\n", range.length == 0,
               !line.trimmingCharacters(in: .whitespaces).isEmpty {
                let prefix = source.substring(with: NSRange(location: paragraph.location, length: caret.location - paragraph.location)).prefix(while: { $0 == " " || $0 == "\t" })
                let newline = "\n" + prefix
                registerUndo(text: NSAttributedString(attributedString: storage), selection: caret, attributes: textView.typingAttributes)
                let next = NSMutableAttributedString(attributedString: storage)
                next.replaceCharacters(in: range, with: NSAttributedString(string: newline, attributes: textView.typingAttributes))
                apply(text: next, selection: NSRange(location: range.location + newline.utf16.count, length: 0), attributes: textView.typingAttributes)
                return false
            }
            var contextual: MarkdownShortcut.Edit?
            if replacement == "\n", range.length == 0 {
                if role?.hasPrefix("heading:") == true {
                    contextual = .init(range: range, replacement: "\n", style: .body)
                } else if code?.hasPrefix("block:") == true, line.trimmingCharacters(in: .whitespaces).isEmpty {
                    contextual = .init(range: NSRange(location: paragraph.location, length: caret.location - paragraph.location), replacement: "", style: quoted ? .quote : .body)
                } else if role == "task" {
                    contextual = line.trimmingCharacters(in: .whitespaces).isEmpty
                        ? .init(range: range, replacement: "", style: quoted ? .quote : .body)
                        : .init(range: range, replacement: "\n" + line.prefix(while: { $0 == "\t" }), style: .task)
                } else if quoted {
                    contextual = line.trimmingCharacters(in: .whitespaces).isEmpty
                        ? .init(range: range, replacement: "", style: .body)
                        : .init(range: range, replacement: "\n", style: .quote)
                } else if code == "inline" {
                    contextual = .init(range: range, replacement: "\n", style: .body)
                }
            }
            if replacement.isEmpty, range.length > 0,
               let item = MarkdownShortcut.listPrefix(line), item.style == .quote,
               line.dropFirst(item.prefix.count).isEmpty,
               NSMaxRange(range) == paragraph.location + item.prefix.utf16.count,
               range.location >= paragraph.location, paragraph.location > 0 {
                let previousRange = source.paragraphRange(for: NSRange(location: paragraph.location - 1, length: 0))
                let previousLine = source.substring(with: previousRange).trimmingCharacters(in: .newlines)
                if MarkdownShortcut.listPrefix(previousLine)?.style == .quote {
                    // AppKit may temporarily expose the collapsed marker as the
                    // selection being deleted. Use the affected range rather than
                    // selectedRange so both one- and two-character reports merge.
                    contextual = .init(
                        range: NSRange(location: paragraph.location - 1, length: item.prefix.utf16.count + 1),
                        replacement: "",
                        style: .quote
                    )
                }
            }
            if replacement.isEmpty, caret.length == 0, contextual == nil {
                if range.length > 0, let item = MarkdownShortcut.listPrefix(line),
                   caret.location == paragraph.location + item.prefix.utf16.count,
                   NSMaxRange(range) == caret.location,
                   range.location >= paragraph.location {
                    contextual = .init(range: NSRange(location: paragraph.location, length: item.prefix.utf16.count), replacement: "", style: .body)
                } else if caret.location == paragraph.location,
                          role?.hasPrefix("heading:") == true || role == "quote" || role == "task" || code?.hasPrefix("block:") == true,
                          range.length == 1 || line.trimmingCharacters(in: .whitespaces).isEmpty {
                    contextual = .init(range: NSRange(location: caret.location, length: 0), replacement: "", style: .body)
                }
            }
            if replacement == "\t" || replacement == "\u{19}", caret.length == 0,
               let item = MarkdownShortcut.listPrefix(line) ?? (role == "task" ? ("", "", MarkdownShortcut.Style.task) : nil) {
                if replacement == "\t", line.prefix(while: { $0 == "\t" }).count < 8 {
                    contextual = .init(range: NSRange(location: paragraph.location, length: 0), replacement: "\t", style: item.style)
                } else if replacement == "\u{19}", line.hasPrefix("\t") {
                    contextual = .init(range: NSRange(location: paragraph.location, length: 1), replacement: "", style: item.style)
                } else { return false }
            }
            var shortcut = code == nil ? MarkdownShortcut.match(text: storage.string, range: range, replacement: replacement, hasMarkedText: false) : nil
            if quoted, replacement == "\n", shortcut?.style == .body {
                shortcut = shortcut.map { .init(range: $0.range, replacement: $0.replacement, style: .quote) }
            }
            // A quote is an outer container. When its current line completes a
            // nested Markdown block shortcut (for example a fenced code block),
            // that inner block must win over generic quote continuation.
            if quoted, shortcut != nil { contextual = nil }
            guard let edit = contextual ?? shortcut else {
                if replacement.isEmpty, range.length > 0 {
                    prepareTypingAttributesAfterInlineDeletion(range)
                }
                return true
            }
            var attributes = textView.typingAttributes
            if attributes.removeValue(forKey: .weaveSyntaxColor) != nil {
                #if os(macOS)
                attributes[.foregroundColor] = NSColor.textColor
                #else
                attributes[.foregroundColor] = UIColor.label
                #endif
            }
            let originalAttributes = attributes
            let base = (attributes[.font] as? PlatformFont)
            let font: Font
            switch edit.style {
            case .heading(let level): font = ParagraphEditing.font(for: "heading:\(level)", context: parent.fontContext)
            case .bold: font = base.map { Font(NativeTextAttributes.storedFont($0 as CTFont)).bold() } ?? .body.bold()
            case .italic: font = base.map { Font(NativeTextAttributes.storedFont($0 as CTFont)).italic() } ?? .body.italic()
            case .code: font = .body.monospaced()
            case .codeBlock: font = .body.monospaced()
            case .body, .bullet, .quote, .numbered, .task, .strike: font = .body
            }
            attributes[.font] = NativeTextAttributes.displayFont(font.resolve(in: parent.fontContext).ctFont)
            switch edit.style {
            case .heading(let level):
                attributes[.weaveInlineEmphasis] = 0
                attributes[.weaveParagraphStyle] = "heading:\(level)"
                attributes.removeValue(forKey: .weaveCodeStyle)
                attributes.removeValue(forKey: .weaveCodeLanguage)
                attributes.removeValue(forKey: .weaveSyntaxColor)
                attributes.removeValue(forKey: .weaveTaskChecked)
            case .codeBlock:
                attributes[.weaveCodeStyle] = "block:" + UUID().uuidString
                attributes[.weaveCodeLanguage] = CodeBlockEditing.languageTag(from: line)
                attributes[.weaveParagraphStyle] = "code"
                attributes.removeValue(forKey: .weaveTaskChecked)
            case .body, .bullet, .numbered, .task, .quote:
                switch edit.style {
                case .quote:
                    attributes[.weaveParagraphStyle] = "body"
                    attributes[.weaveQuote] = true
                    #if os(macOS)
                    attributes[.foregroundColor] = NSColor.secondaryLabelColor
                    #else
                    attributes[.foregroundColor] = UIColor.secondaryLabel
                    #endif
                    attributes[.weaveQuoteColor] = true
                    var quoteSample = AttributedString("\n")
                    quoteSample.font = .body
                    quoteSample[ParagraphStyleAttribute.self] = "body"
                    quoteSample[QuoteAttribute.self] = true
                    let nativeQuote = NativeTextAttributes.native(quoteSample, context: parent.fontContext)
                    attributes[.paragraphStyle] = nativeQuote.attribute(.paragraphStyle, at: 0, effectiveRange: nil)
                case .numbered: attributes[.weaveParagraphStyle] = "numbered"
                case .bullet: attributes[.weaveParagraphStyle] = "bullet"
                case .task: attributes[.weaveParagraphStyle] = "task"
                default:
                    attributes[.weaveParagraphStyle] = "body"
                    attributes.removeValue(forKey: .weaveQuote)
                    if attributes.removeValue(forKey: .weaveQuoteColor) != nil {
                        #if os(macOS)
                        attributes[.foregroundColor] = NSColor.textColor
                        #else
                        attributes[.foregroundColor] = UIColor.label
                        #endif
                    }
                    var bodySample = AttributedString("\n")
                    bodySample.font = .body
                    bodySample[ParagraphStyleAttribute.self] = "body"
                    let nativeBody = NativeTextAttributes.native(bodySample, context: parent.fontContext)
                    attributes[.paragraphStyle] = nativeBody.attribute(.paragraphStyle, at: 0, effectiveRange: nil)
                }
                attributes.removeValue(forKey: .weaveCodeStyle)
                attributes.removeValue(forKey: .weaveCodeLanguage)
                attributes.removeValue(forKey: .weaveSyntaxColor)
                attributes[.weaveInlineEmphasis] = 0
                attributes.removeValue(forKey: .link)
                if edit.style == .task { attributes[.weaveTaskChecked] = false }
                else { attributes.removeValue(forKey: .weaveTaskChecked) }
            default: break
            }
            let inserted: NSAttributedString
            switch edit.style {
            case .bold, .italic, .code, .strike:
                let markerLength = edit.style == .bold || edit.style == .strike ? 2 : 1
                let contentRange = NSRange(location: edit.range.location + markerLength, length: edit.replacement.utf16.count)
                let content = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: contentRange))
                content.enumerateAttribute(.font, in: NSRange(location: 0, length: content.length)) { value, runRange, _ in
                    let existing = (value as? PlatformFont).map { Font(NativeTextAttributes.storedFont($0 as CTFont)) } ?? .body
                    let styled: Font = edit.style == .bold ? existing.weight(.bold) : edit.style == .italic ? existing.italic() : edit.style == .code ? DocumentTypography.font(for: role ?? "body", inlineCode: true, context: parent.fontContext) : existing
                    content.addAttribute(.font, value: NativeTextAttributes.displayFont(styled.resolve(in: parent.fontContext).ctFont), range: runRange)
                }
                if edit.style == .bold || edit.style == .italic {
                    let flag = edit.style == .bold ? 1 : 2
                    content.enumerateAttribute(.weaveInlineEmphasis, in: NSRange(location: 0, length: content.length)) { value, runRange, _ in
                        content.addAttribute(.weaveInlineEmphasis, value: (value as? Int ?? 0) | flag, range: runRange)
                    }
                }
                if edit.style == .strike {
                    content.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: 0, length: content.length))
                }
                if edit.style == .code {
                    content.addAttribute(.weaveCodeStyle, value: "inline", range: NSRange(location: 0, length: content.length))
                    content.removeAttribute(.backgroundColor, range: NSRange(location: 0, length: content.length))
                }
                inserted = content
            default:
                inserted = NSAttributedString(string: edit.replacement, attributes: attributes)
            }
            let updated = NSMutableAttributedString(attributedString: storage)
            updated.replaceCharacters(in: edit.range, with: inserted)
            // Persist the empty paragraph's boundary, otherwise the native view can
            // inherit code/quote attributes from a neighboring newline. When content
            // follows an empty quote marker, its terminating newline is at the edit
            // location after the marker is removed; at the end of the document the
            // preceding newline carries the empty paragraph's typing state instead.
            if edit.style == .body, replacement == "\n", inserted.length == 0 {
                let boundary: Int?
                if edit.range.location < updated.length,
                   (updated.string as NSString).substring(with: NSRange(location: edit.range.location, length: 1)) == "\n" {
                    boundary = edit.range.location
                } else if edit.range.location > 0,
                          (updated.string as NSString).substring(with: NSRange(location: edit.range.location - 1, length: 1)) == "\n" {
                    boundary = edit.range.location - 1
                } else {
                    boundary = nil
                }
                if let boundary {
                    updated.setAttributes(attributes, range: NSRange(location: boundary, length: 1))
                }
            }
            let after: NSRange
            if replacement == "\t" || replacement == "\u{19}" {
                after = NSRange(location: caret.location + inserted.length - edit.range.length, length: 0)
            } else { after = NSRange(location: edit.range.location + inserted.length, length: 0) }
            if edit.style == .body, contextual != nil, replacement != "\n", updated.length > after.location {
                let affected = (updated.string as NSString).paragraphRange(for: NSRange(location: after.location, length: 0))
                updated.removeAttribute(.weaveCodeStyle, range: affected)
                updated.removeAttribute(.weaveCodeLanguage, range: affected)
                updated.removeAttribute(.weaveTaskChecked, range: affected)
                updated.addAttribute(.weaveParagraphStyle, value: "body", range: affected)
                updated.addAttribute(.font, value: attributes[.font]!, range: affected)
            }
            let nextAttributes: [NSAttributedString.Key: Any]
            switch edit.style {
            case .bold, .italic, .code, .strike: nextAttributes = originalAttributes
            default: nextAttributes = attributes
            }
            // Register the raw typed marker as the undo state: one undo restores syntax,
            // without triggering the shortcut again through the input delegate.
            let raw = NSMutableAttributedString(attributedString: storage)
            if contextual == nil { raw.replaceCharacters(in: range, with: NSAttributedString(string: replacement, attributes: originalAttributes)) }
            registerUndo(text: raw, selection: contextual == nil ? NSRange(location: range.location + replacement.utf16.count, length: 0) : caret, attributes: originalAttributes)
            apply(text: updated, selection: after, attributes: nextAttributes)
            textView.undoManager?.setActionName("Markdown 快捷输入")
            return false
        }

        func exitTrailingCode() -> Bool {
            guard !hasMarkedText, let storage, let view = textView, storage.length > 0,
                  (storage.attribute(.weaveCodeStyle, at: storage.length - 1, effectiveRange: nil) as? String)?.hasPrefix("block:") == true else { return false }
            var body = AttributedString("\n")
            body.font = .body
            body[ParagraphStyleAttribute.self] = "body"
            let boundary = NativeTextAttributes.native(body, context: parent.fontContext)
            let attributes = boundary.attributes(at: 0, effectiveRange: nil)
            registerUndo(text: NSAttributedString(attributedString: storage), selection: currentSelection, attributes: view.typingAttributes)
            let next = NSMutableAttributedString(attributedString: storage)
            if next.string.hasSuffix("\n") {
                next.setAttributes(attributes, range: NSRange(location: next.length - 1, length: 1))
            } else { next.append(boundary) }
            apply(text: next, selection: NSRange(location: next.length, length: 0), attributes: attributes)
            view.undoManager?.setActionName("退出代码块")
            return true
        }

        fileprivate func exitEmptyQuote() -> Bool {
            guard !hasMarkedText, let storage, let view = textView,
                  storage.length == 0,
                  currentSelection == NSRange(location: 0, length: 0),
                  view.typingAttributes[.weaveQuote] as? Bool == true else { return false }
            var body = AttributedString(" ")
            body.font = .body
            body[ParagraphStyleAttribute.self] = "body"
            var attributes = NativeTextAttributes.native(body, context: parent.fontContext).attributes(at: 0, effectiveRange: nil)
            attributes.removeValue(forKey: .weaveQuote)
            attributes.removeValue(forKey: .weaveQuoteColor)
            registerUndo(text: NSAttributedString(attributedString: storage), selection: currentSelection, attributes: view.typingAttributes)
            apply(text: NSAttributedString(attributedString: storage), selection: currentSelection, attributes: attributes)
            view.undoManager?.setActionName("退出引用")
            return true
        }

        fileprivate func toggleTask(at index: Int) -> Bool {
            guard !hasMarkedText, let storage, let view = textView, index < storage.length else { return false }
            let source = storage.string as NSString
            let paragraph = source.paragraphRange(for: NSRange(location: index, length: 0))
            guard let layout = view.layoutManager as? CodeLayoutManager,
                  let markerIndex = layout.taskMarkerIndex(in: paragraph), index == markerIndex else { return false }
            let checked = storage.attribute(.weaveTaskChecked, at: markerIndex, effectiveRange: nil) as? Bool ?? false
            registerUndo(text: NSAttributedString(attributedString: storage), selection: currentSelection, attributes: view.typingAttributes)
            let updated = NSMutableAttributedString(attributedString: storage)
            updated.addAttribute(.weaveTaskChecked, value: !checked, range: paragraph)
            apply(text: updated, selection: currentSelection, attributes: view.typingAttributes)
            view.undoManager?.setActionName("切换待办")
            return true
        }

        func toggleEmptyTask() -> Bool {
            guard !hasMarkedText, let storage, let view = textView,
                  currentSelection.length == 0,
                  view.typingAttributes[.weaveParagraphStyle] as? String == "task",
                  let checked = view.typingAttributes[.weaveTaskChecked] as? Bool else { return false }
            registerUndo(
                text: NSAttributedString(attributedString: storage),
                selection: currentSelection,
                attributes: view.typingAttributes
            )
            var attributes = view.typingAttributes
            attributes[.weaveTaskChecked] = !checked
            apply(
                text: NSAttributedString(attributedString: storage),
                selection: currentSelection,
                attributes: attributes
            )
            view.undoManager?.setActionName("切换待办")
            return true
        }

        fileprivate func moveCaretBeforeTask() -> Bool {
            false
        }

        private func registerUndo(text: NSAttributedString, selection: NSRange, attributes: [NSAttributedString.Key: Any]) {
            textView?.undoManager?.registerUndo(withTarget: self) { coordinator in
                MainActor.assumeIsolated {
                    guard let current = coordinator.storage, let view = coordinator.textView else { return }
                    coordinator.registerUndo(text: NSAttributedString(attributedString: current), selection: coordinator.currentSelection, attributes: view.typingAttributes)
                    coordinator.apply(text: text, selection: selection, attributes: attributes)
                }
            }
        }

        private func prepareTypingAttributesAfterInlineDeletion(_ deletion: NSRange) {
            guard let storage, let view = textView, deletion.location < storage.length else { return }
            let source = storage.string as NSString
            let paragraph = source.paragraphRange(for: NSRange(location: deletion.location, length: 0))
            let limit = NSIntersectionRange(paragraph, NSRange(location: 0, length: storage.length))
            var resetCode = false
            var resetEmphasis = 0
            var resetStrike = false
            var resetUnderline = false
            var resetLink = false
            var location = deletion.location
            let end = min(NSMaxRange(deletion), storage.length)
            while location < end {
                var effective = NSRange()
                let attributes = storage.attributes(at: location, longestEffectiveRange: &effective, in: limit)
                let fullyDeleted = deletion.location <= effective.location && NSMaxRange(deletion) >= NSMaxRange(effective)
                if fullyDeleted {
                    if attributes[.weaveCodeStyle] as? String == "inline" { resetCode = true }
                    resetEmphasis |= attributes[.weaveInlineEmphasis] as? Int ?? 0
                    resetStrike = resetStrike || (attributes[.strikethroughStyle] as? Int ?? 0) != 0
                    resetUnderline = resetUnderline || (attributes[.underlineStyle] as? Int ?? 0) != 0
                    resetLink = resetLink || attributes[.link] != nil
                }
                location = max(location + 1, NSMaxRange(effective))
            }
            guard resetCode || resetEmphasis != 0 || resetStrike || resetUnderline || resetLink else { return }
            var attributes = view.typingAttributes
            let role = attributes[.weaveParagraphStyle] as? String
                ?? storage.attribute(.weaveParagraphStyle, at: deletion.location, effectiveRange: nil) as? String
                ?? "body"
            var emphasis = attributes[.weaveInlineEmphasis] as? Int ?? 0
            emphasis &= ~resetEmphasis
            attributes[.weaveInlineEmphasis] = emphasis
            if resetCode {
                attributes.removeValue(forKey: .weaveCodeStyle)
                attributes.removeValue(forKey: .weaveCodeLanguage)
                attributes.removeValue(forKey: .weaveSyntaxColor)
                attributes.removeValue(forKey: .weaveInlineSpacing)
                attributes.removeValue(forKey: .kern)
                attributes.removeValue(forKey: .backgroundColor)
            }
            if resetStrike { attributes.removeValue(forKey: .strikethroughStyle) }
            if resetUnderline { attributes.removeValue(forKey: .underlineStyle) }
            if resetLink { attributes.removeValue(forKey: .link) }
            attributes[.font] = NativeTextAttributes.displayFont(
                DocumentTypography.font(for: role, emphasis: emphasis, context: parent.fontContext).resolve(in: parent.fontContext).ctFont
            )
            pendingTypingAttributesAfterInlineDeletion = attributes
        }

        fileprivate func restoreEmptyQuoteTypingAttributesFromPreviousValue() {
            guard !isUpdating, let storage, let view = textView,
                  storage.length < lastNativeValue.length,
                  lastNativeValue.length > 0 else { return }
            let source = storage.string as NSString
            let insertion = min(currentSelection.location, source.length)
            let paragraph = source.paragraphRange(for: NSRange(location: insertion, length: 0))
            guard source.substring(with: paragraph).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            let anchor = min(insertion, lastNativeValue.length - 1)
            guard lastNativeValue.attribute(.weaveQuote, at: anchor, effectiveRange: nil) as? Bool == true else { return }
            var attributes = lastNativeValue.attributes(at: anchor, effectiveRange: nil)
            attributes.removeValue(forKey: .attachment)
            attributes.removeValue(forKey: .weaveTable)
            attributes[.weaveQuote] = true
            view.typingAttributes = attributes
            #if os(macOS)
            (view as? ReadingMacTextView)?.updateEmptyQuoteBar()
            #else
            view.setNeedsDisplay()
            #endif
        }

        private func apply(text: NSAttributedString, selection: NSRange, attributes: [NSAttributedString.Key: Any]) {
            isUpdating = true
            storage?.setAttributedString(text)
            setSelection(selection)
            textView?.typingAttributes = attributes
            locallyAppliedTypingAttributes = attributes
            #if os(macOS)
            textView?.didChangeText()
            textView?.needsDisplay = true
            (textView as? ReadingMacTextView)?.updateEmptyQuoteBar()
            #else
            textView?.setNeedsDisplay()
            #endif
            isUpdating = false
            publish()
        }
    }
}

#if os(macOS)
final class ReadingMacTextView: NSTextView {
    private final class QuoteDecorationView: NSView {
        weak var owner: ReadingMacTextView?

        override var isFlipped: Bool { true }
        override var isOpaque: Bool { false }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func draw(_ dirtyRect: NSRect) {
            NSColor.clear.setFill()
            dirtyRect.fill(using: .copy)
            owner?.drawQuoteDecorations()
        }
    }

    private var quoteDecorationView: QuoteDecorationView!
    private var taskTrackingArea: NSTrackingArea?
    private var isHoveringEmptyTask = false {
        didSet {
            if isHoveringEmptyTask != oldValue { needsDisplay = true }
        }
    }
    var exitTrailingCode: (() -> Bool)?
    var didResolveTypingAttributes: (() -> Void)?
    var toggleTask: ((Int) -> Bool)?
    var toggleEmptyTask: (() -> Bool)?
    var copyStructured: ((Bool) -> Bool)?
    var pasteStructured: (() -> Bool)?
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        installQuoteDecorationView()
    }
    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        installQuoteDecorationView()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        installQuoteDecorationView()
    }
    private func installQuoteDecorationView() {
        guard quoteDecorationView == nil else { return }
        let decoration = QuoteDecorationView(frame: bounds)
        decoration.owner = self
        decoration.autoresizingMask = [.width, .height]
        decoration.setAccessibilityElement(false)
        addSubview(decoration)
        quoteDecorationView = decoration
    }
    override func copy(_ sender: Any?) { if copyStructured?(false) != true { super.copy(sender) } }
    override func cut(_ sender: Any?) { if copyStructured?(true) != true { super.cut(sender) } }
    override func paste(_ sender: Any?) { if pasteStructured?() != true { super.paste(sender) } }
    func emptyQuoteBarDrawingRect() -> CGRect? {
        let selection = selectedRange()
        let source = string as NSString
        let insertion = min(selection.location, source.length)
        let paragraph = source.paragraphRange(for: NSRange(location: insertion, length: 0))
        guard selection.length == 0,
              source.substring(with: paragraph).trimmingCharacters(in: .newlines).isEmpty,
              typingAttributes[.weaveQuote] as? Bool == true,
              let layout = layoutManager as? CodeLayoutManager,
              let container = textContainer else {
            return nil
        }
        if paragraph.location < (textStorage?.length ?? 0),
           textStorage?.attribute(.weaveQuote, at: paragraph.location, effectiveRange: nil) as? Bool == true {
            return nil
        }
        let font = typingAttributes[.font] as? NSFont ?? .systemFont(ofSize: DocumentTypography.bodySize)
        return layout.emptyQuoteBarRect(at: insertion, font: font, in: container).offsetBy(
            dx: textContainerOrigin.x,
            dy: textContainerOrigin.y
        )
    }
    func emptyTaskMarkerDrawingRect() -> CGRect? {
        let selection = selectedRange()
        let source = string as NSString
        let insertion = min(selection.location, source.length)
        let paragraph = source.paragraphRange(for: NSRange(location: insertion, length: 0))
        guard selection.length == 0,
              source.substring(with: paragraph).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              typingAttributes[.weaveParagraphStyle] as? String == "task",
              typingAttributes[.weaveTaskChecked] is Bool,
              let layout = layoutManager as? CodeLayoutManager,
              let container = textContainer else { return nil }
        if paragraph.location < (textStorage?.length ?? 0),
           layout.taskMarkerIndex(in: paragraph) != nil { return nil }
        let font = typingAttributes[.font] as? NSFont
            ?? .systemFont(ofSize: DocumentTypography.bodySize * DocumentTypography.readingScale)
        return layout.emptyTaskMarkerRect(
            at: insertion,
            font: font,
            quoted: typingAttributes[.weaveQuote] as? Bool == true,
            in: container
        ).offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
    }
    fileprivate func updateEmptyQuoteBar() {
        if let layout = layoutManager as? CodeLayoutManager {
            layout.emptyLineHeadIndent = string.isEmpty
                && typingAttributes[.weaveQuote] as? Bool == true
                ? DocumentTypography.quoteIndent
                : 0
        }
        quoteDecorationView?.needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        quoteDecorationView?.needsDisplay = true
        guard let layout = layoutManager as? CodeLayoutManager,
              let rect = emptyTaskMarkerDrawingRect() else { return }
        layout.drawTaskMarker(
            checked: typingAttributes[.weaveTaskChecked] as? Bool ?? false,
            hovered: isHoveringEmptyTask,
            in: rect
        )
    }
    private func drawQuoteDecorations() {
        guard let layout = layoutManager as? CodeLayoutManager,
              let container = textContainer else { return }
        let origin = textContainerOrigin
        let localVisible = visibleRect.offsetBy(dx: -origin.x, dy: -origin.y)
        let glyphs = layout.glyphRange(forBoundingRect: localVisible, in: container)
        let emptyBar = emptyQuoteBarDrawingRect()
        let mergedEmptyBar = layout.drawQuoteBars(
            forGlyphRange: glyphs,
            at: origin,
            trailingEmptyBar: emptyBar
        )
        if let rect = emptyBar, !mergedEmptyBar {
            NSColor.labelColor.withAlphaComponent(0.22).setFill()
            layout.fill(rect, radius: 1)
        }
    }
    var editLink: (() -> Void)?
    var refreshTables: (() -> Void)?
    override func accessibilityChildren() -> [Any]? {
        (super.accessibilityChildren() ?? []) + subviews.filter { $0 !== quoteDecorationView }
    }
    override func layout() {
        super.layout()
        quoteDecorationView?.frame = bounds
        refreshTables?()
        window?.invalidateCursorRects(for: self)
    }
    override func resetCursorRects() {
        super.resetCursorRects()
        if let layout = layoutManager as? CodeLayoutManager,
           let rect = emptyTaskMarkerDrawingRect() {
            addCursorRect(layout.taskMarkerHitRect(for: rect), cursor: .pointingHand)
        }
        guard let layout = layoutManager as? CodeLayoutManager, let container = textContainer,
              let storage = textStorage, storage.length > 0 else { return }
        layout.ensureLayout(for: container)
        let origin = textContainerOrigin
        let localVisible = visibleRect.offsetBy(dx: -origin.x, dy: -origin.y)
        let glyphs = layout.glyphRange(forBoundingRect: localVisible, in: container)
        let visible = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        let source = storage.string as NSString
        var location = source.paragraphRange(for: NSRange(location: visible.location, length: 0)).location
        let end = min(storage.length, NSMaxRange(visible))
        while location < end {
            let paragraph = source.paragraphRange(for: NSRange(location: location, length: 0))
            if let marker = layout.taskMarkerIndex(in: paragraph), let rect = layout.taskMarkerHitRect(at: marker) {
                addCursorRect(rect.offsetBy(dx: origin.x, dy: origin.y), cursor: .pointingHand)
            }
            let next = NSMaxRange(paragraph)
            if next <= location { break }
            location = next
        }
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let taskTrackingArea { removeTrackingArea(taskTrackingArea) }
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        taskTrackingArea = trackingArea
    }
    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        updateHoveredTask(with: event)
    }
    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        updateHoveredTask(with: event)
    }
    override func cursorUpdate(with event: NSEvent) {
        if taskMarker(at: event) != nil || isEmptyTaskMarker(at: event) {
            NSCursor.pointingHand.set()
        } else {
            super.cursorUpdate(with: event)
        }
    }
    override func mouseExited(with event: NSEvent) {
        (layoutManager as? CodeLayoutManager)?.hoveredTaskMarker = nil
        isHoveringEmptyTask = false
        super.mouseExited(with: event)
    }
    private func updateHoveredTask(with event: NSEvent) {
        guard let layout = layoutManager as? CodeLayoutManager else { return }
        let marker = taskMarker(at: event)
        layout.hoveredTaskMarker = marker
        isHoveringEmptyTask = isEmptyTaskMarker(at: event)
        if marker != nil || isHoveringEmptyTask { NSCursor.pointingHand.set() }
    }
    private func taskMarker(at event: NSEvent) -> Int? {
        guard let layout = layoutManager as? CodeLayoutManager, let textContainer else { return nil }
        let point = convert(event.locationInWindow, from: nil)
        let local = CGPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        return layout.taskMarkerCharacter(at: local, in: textContainer)
    }
    private func isEmptyTaskMarker(at event: NSEvent) -> Bool {
        guard let layout = layoutManager as? CodeLayoutManager,
              let marker = emptyTaskMarkerDrawingRect() else { return false }
        let point = convert(event.locationInWindow, from: nil)
        return layout.taskMarkerHitRect(for: marker).contains(point)
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers == "k", selectedRange().length > 0 {
            editLink?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if isEmptyTaskMarker(at: event), toggleEmptyTask?() == true {
            window?.makeFirstResponder(self)
            return
        }
        if let layoutManager, let textContainer {
            let local = CGPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
            if let layout = layoutManager as? CodeLayoutManager, let storage = textStorage, storage.length > 0 {
                var range = NSRange()
                if let code = storage.attribute(.weaveCodeStyle, at: storage.length - 1, effectiveRange: &range) as? String,
                   code.hasPrefix("block:") {
                    let glyphs = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                    if local.y > layout.codeBackgroundRect(forGlyphRange: glyphs, in: textContainer).maxY,
                       exitTrailingCode?() == true {
                        window?.makeFirstResponder(self)
                        needsDisplay = true
                        return
                    }
                }
            }
            if let layout = layoutManager as? CodeLayoutManager,
               let marker = layout.taskMarkerCharacter(at: local, in: textContainer),
               toggleTask?(marker) == true {
                window?.makeFirstResponder(self)
                return
            }
        }
        super.mouseDown(with: event)
        resolveEmptyParagraphTypingAttributes()
    }

    func resolveEmptyParagraphTypingAttributes() {
        // AppKit inherits attributes from the preceding character at a boundary.
        // An existing empty paragraph owns its format, including a body newline
        // directly after code. Resolve this only after a mouse selection, so
        // explicit toolbar formatting and keyboard continuation remain intact.
        if selectedRange().length == 0, !hasMarkedText(), let storage = textStorage {
            let source = storage.string as NSString
            let paragraph = source.paragraphRange(for: NSRange(location: min(selectedRange().location, source.length), length: 0))
            if paragraph.length > 0,
               source.substring(with: paragraph).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                typingAttributes = storage.attributes(at: paragraph.location, effectiveRange: nil)
                didResolveTypingAttributes?()
            }
        }
    }
}

private final class ReadingScrollView: NSScrollView {
    override func tile() {
        super.tile()
        guard let view = documentView as? NSTextView else { return }
        let inset = max(32, (contentSize.width - DocumentTypography.readingWidth) / 2)
        if view.textContainerInset.width != inset {
            view.textContainerInset = NSSize(width: inset, height: DocumentTypography.editorTopInset)
        }
    }
}

extension NativeRichTextEditor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = ReadingScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        let view = ReadingMacTextView(frame: scroll.contentView.bounds)
        view.exitTrailingCode = { [weak coordinator = context.coordinator] in coordinator?.exitTrailingCode() ?? false }
        view.didResolveTypingAttributes = { [weak coordinator = context.coordinator] in coordinator?.publishSelection() }
        view.copyStructured = { [weak coordinator = context.coordinator] cut in coordinator?.copyStructured(cut: cut) ?? false }
        view.pasteStructured = { [weak coordinator = context.coordinator] in coordinator?.pasteStructured() ?? false }
        view.refreshTables = { [weak coordinator = context.coordinator] in coordinator?.refreshTables() }
        view.editLink = { [weak coordinator = context.coordinator] in coordinator?.parent.onEditLink() }
        view.toggleTask = { [weak coordinator = context.coordinator] index in coordinator?.toggleTask(at: index) ?? false }
        view.toggleEmptyTask = { [weak coordinator = context.coordinator] in coordinator?.toggleEmptyTask() ?? false }
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.minSize = .zero
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.textContainer?.replaceLayoutManager(CodeLayoutManager())
        view.textContainer?.widthTracksTextView = true
        scroll.documentView = view
        view.isRichText = true
        view.allowsUndo = true
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.textContainerInset = NSSize(width: 32, height: DocumentTypography.editorTopInset)
        view.setAccessibilityLabel("记录正文")
        view.setAccessibilityIdentifier("note-editor")
        view.textStorage?.setAttributedString(NativeTextAttributes.native(text, context: fontContext))
        view.delegate = context.coordinator
        context.coordinator.textView = view
        context.coordinator.update(self)
        if focusWhenEmpty, text.characters.isEmpty {
            DispatchQueue.main.async { [weak view] in view?.window?.makeFirstResponder(view) }
        }
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) { context.coordinator.update(self) }
}

extension NativeRichTextEditor.Coordinator: NSTextViewDelegate {
    func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
        intercept(range: affectedCharRange, replacement: replacementString)
    }
    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.moveBackward(_:)) || selector == #selector(NSResponder.moveLeft(_:)),
           moveCaretBeforeTask() {
            return true
        }
        if selector == #selector(NSResponder.deleteBackward(_:)),
           textView.string.isEmpty,
           textView.selectedRange() == NSRange(location: 0, length: 0) {
            // AppKit does not ask shouldChangeTextIn for a no-op deletion at the
            // beginning of an empty document. Route the command through the same
            // contextual edit so an empty heading/quote/code block can return to body.
            if exitEmptyQuote() { return true }
            return !intercept(range: textView.selectedRange(), replacement: "")
        }
        if selector == #selector(NSResponder.insertBacktab(_:)) {
            return !intercept(range: textView.selectedRange(), replacement: "\u{19}")
        }
        if selector == #selector(NSResponder.insertTab(_:)) {
            return !intercept(range: textView.selectedRange(), replacement: "\t")
        }
        if selector == #selector(NSResponder.insertLineBreak(_:)) {
            textView.insertText("\u{2028}", replacementRange: textView.selectedRange())
            return true
        }
        return false
    }
    func textDidChange(_ notification: Notification) {
        restoreEmptyQuoteTypingAttributesFromPreviousValue()
        if let attributes = pendingTypingAttributesAfterInlineDeletion {
            textView?.typingAttributes = attributes
            pendingTypingAttributesAfterInlineDeletion = nil
        }
        publish()
    }
    func textViewDidChangeSelection(_ notification: Notification) {
        (textView as? ReadingMacTextView)?.updateEmptyQuoteBar()
        publishSelection()
    }
}
#else
private final class ReadingTextView: UITextView, UIGestureRecognizerDelegate {
    var exitEmptyQuote: (() -> Bool)?
    var copyStructured: ((Bool) -> Bool)?
    var pasteStructured: (() -> Bool)?
    override func copy(_ sender: Any?) { if copyStructured?(false) != true { super.copy(sender) } }
    override func cut(_ sender: Any?) { if copyStructured?(true) != true { super.cut(sender) } }
    override func paste(_ sender: Any?) { if pasteStructured?() != true { super.paste(sender) } }
    override func deleteBackward() {
        if text.isEmpty, selectedRange == NSRange(location: 0, length: 0), exitEmptyQuote?() == true { return }
        super.deleteBackward()
    }
    override func draw(_ rect: CGRect) {
        super.draw(rect)
        let source = text as NSString
        let insertion = min(selectedRange.location, source.length)
        let paragraph = source.paragraphRange(for: NSRange(location: insertion, length: 0))
        guard selectedRange.length == 0,
              source.substring(with: paragraph).trimmingCharacters(in: .newlines).isEmpty,
              typingAttributes[.weaveQuote] as? Bool == true,
              let layout = layoutManager as? CodeLayoutManager else { return }
        if paragraph.location < textStorage.length,
           textStorage.attribute(.weaveQuote, at: paragraph.location, effectiveRange: nil) as? Bool == true { return }
        let font = typingAttributes[.font] as? UIFont ?? .systemFont(ofSize: DocumentTypography.bodySize)
        UIColor.label.withAlphaComponent(0.22).setFill()
        layout.fill(layout.emptyQuoteBarRect(at: insertion, font: font, in: textContainer).offsetBy(
            dx: textContainerInset.left,
            dy: textContainerInset.top
        ), radius: 1)
    }
    var refreshTables: (() -> Void)?
    var toggleTask: ((Int) -> Bool)?
    @objc func tappedTask(_ recognizer: UITapGestureRecognizer) {
        let point = recognizer.location(in: self)
        let local = CGPoint(x: point.x - textContainerInset.left, y: point.y - textContainerInset.top)
        guard let layout = layoutManager as? CodeLayoutManager,
              let marker = layout.taskMarkerCharacter(at: local, in: textContainer) else { return }
        _ = toggleTask?(marker)
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer is UITapGestureRecognizer,
              let layout = layoutManager as? CodeLayoutManager else { return true }
        let point = touch.location(in: self)
        let local = CGPoint(x: point.x - textContainerInset.left, y: point.y - textContainerInset.top)
        return layout.taskMarkerCharacter(at: local, in: textContainer) != nil
    }

    override func layoutSubviews() {
        let inset = max(24, (bounds.width - DocumentTypography.readingWidth) / 2)
        if textContainerInset.left != inset {
            textContainerInset = UIEdgeInsets(top: DocumentTypography.editorTopInset, left: inset, bottom: 40, right: inset)
        }
        super.layoutSubviews()
        refreshTables?()
    }
}

extension NativeRichTextEditor: UIViewRepresentable {
    func makeUIView(context: Context) -> UITextView {
        let storage = NSTextStorage()
        let layout = CodeLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.addTextContainer(container)
        let view = ReadingTextView(frame: .zero, textContainer: container)
        view.exitEmptyQuote = { [weak coordinator = context.coordinator] in coordinator?.exitEmptyQuote() ?? false }
        view.copyStructured = { [weak coordinator = context.coordinator] cut in coordinator?.copyStructured(cut: cut) ?? false }
        view.pasteStructured = { [weak coordinator = context.coordinator] in coordinator?.pasteStructured() ?? false }
        view.refreshTables = { [weak coordinator = context.coordinator] in coordinator?.refreshTables() }
        view.toggleTask = { [weak coordinator = context.coordinator] index in coordinator?.toggleTask(at: index) ?? false }
        let tap = UITapGestureRecognizer(target: view, action: #selector(ReadingTextView.tappedTask(_:)))
        tap.delegate = view
        tap.cancelsTouchesInView = true
        view.addGestureRecognizer(tap)
        view.font = .preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.textContainerInset = UIEdgeInsets(top: DocumentTypography.editorTopInset, left: 8, bottom: 40, right: 8)
        view.allowsEditingTextAttributes = true
        view.smartQuotesType = .no
        view.smartDashesType = .no
        view.accessibilityLabel = "记录正文"
        view.accessibilityIdentifier = "note-editor"
        view.attributedText = NativeTextAttributes.native(text, context: fontContext)
        view.delegate = context.coordinator
        context.coordinator.textView = view
        context.coordinator.update(self)
        if focusWhenEmpty, text.characters.isEmpty {
            DispatchQueue.main.async { [weak view] in view?.becomeFirstResponder() }
        }
        return view
    }
    func updateUIView(_ uiView: UITextView, context: Context) { context.coordinator.update(self) }
}

extension NativeRichTextEditor.Coordinator: UITextViewDelegate {
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        intercept(range: range, replacement: text)
    }
    func textViewDidChange(_ textView: UITextView) {
        restoreEmptyQuoteTypingAttributesFromPreviousValue()
        if let attributes = pendingTypingAttributesAfterInlineDeletion {
            textView.typingAttributes = attributes
            pendingTypingAttributesAfterInlineDeletion = nil
        }
        publish()
    }
    func textViewDidChangeSelection(_ textView: UITextView) { publishSelection() }
}
#endif
