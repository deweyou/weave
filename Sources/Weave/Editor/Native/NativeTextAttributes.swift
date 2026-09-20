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
                    let container = textContainers.first
                else { return }
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
            let paragraph = storage.attribute(.paragraphStyle, at: storage.length - 1, effectiveRange: nil) as? NSParagraphStyle
        {
            // An open code paragraph belongs to the surface even when the caret leaves it.
            // Do not use extraLineFragmentRect: its metrics depend on current typing attributes.
            bounds.size.height += paragraph.minimumLineHeight + paragraph.lineSpacing
        }
        let quoteInset: CGFloat
        if let storage = textStorage,
            storage.attribute(.weaveQuote, at: characterRange(forGlyphRange: glyphs, actualGlyphRange: nil).location, effectiveRange: nil)
                as? Bool == true
        {
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
                return (storage.attribute(.weaveCodeStyle, at: paragraph.location, effectiveRange: nil) as? String)?.hasPrefix("block:")
                    == true
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
            let canonicalFont =
                CTFontCreateUIFontForLanguage(.system, fontSize, nil)
                ?? NSFont.systemFont(ofSize: fontSize) as CTFont
            let attributes: [NSAttributedString.Key: Any] = [
                // Use the concrete SF font behind SwiftUI's body role. The dynamic
                // `.AppleSystemUIFont` placeholder has different fractional leading.
                .font: canonicalFont as NSFont,
                .paragraphStyle: style,
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
            let height =
                fixedHeight > 0
                ? fixedHeight
                : font.map(NativeTextAttributes.stableLineHeight) ?? fragment.height
            bounds = bounds.union(CGRect(x: fragment.minX, y: fragment.minY, width: fragment.width, height: height))
        }
        guard !bounds.isNull else { return .zero }
        let characters = characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        let fontSize =
            characters.location < storage.length
            ? (storage.attribute(.font, at: characters.location, effectiveRange: nil) as? PlatformFont)?.pointSize
                ?? DocumentTypography.bodySize
            : DocumentTypography.bodySize
        // Keep the bar airy inside a quote, but stop it at the final quote
        // fragment once the following paragraph has returned to body style.
        // Otherwise its overshoot visually collides with the body caret.
        let rangeEnd = NSMaxRange(characters)
        let endsAtOpenQuote = rangeEnd == storage.length && !storage.string.hasSuffix("\n")
        let continuesQuote =
            rangeEnd < storage.length
            && storage.attribute(.weaveQuote, at: rangeEnd, effectiveRange: nil) as? Bool == true
        return quoteBarRect(
            forLineBounds: bounds,
            fontSize: fontSize,
            extendsBelow: endsAtOpenQuote || continuesQuote,
            in: container
        )
    }

    private func quoteBarRect(
        forLineBounds bounds: CGRect, fontSize: CGFloat,
        extendsBelow: Bool, in container: NSTextContainer
    ) -> CGRect {
        let overshoot = fontSize * DocumentTypography.quoteBarVerticalOvershootRatio
        let opticalRise = fontSize * DocumentTypography.quoteBarOpticalRiseRatio
        let bottomOvershoot =
            extendsBelow
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
        let continuesQuote =
            insertion < storageLength
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

    func layoutManager(
        _ layoutManager: NSLayoutManager, shouldSetLineFragmentRect lineFragmentRect: UnsafeMutablePointer<CGRect>,
        lineFragmentUsedRect: UnsafeMutablePointer<CGRect>, baselineOffset: UnsafeMutablePointer<CGFloat>,
        in textContainer: NSTextContainer, forGlyphRange glyphRange: NSRange
    ) -> Bool {
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
                    let baseFontSize =
                        codeStyle == "inline"
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
        guard
            let id = storage.attribute(
                .weaveCodeStyle, at: character, longestEffectiveRange: &range, in: NSRange(location: 0, length: storage.length)) as? String,
            id.hasPrefix("block:"), character == range.location
        else { return true }
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
                let paragraph = storage.attribute(.paragraphStyle, at: characters.location, effectiveRange: nil) as? NSParagraphStyle
            else { return 0 }
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
                let container = self.textContainer(forGlyphAt: glyphs.location, effectiveRange: nil)
            else { return }
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
                    self.fill(
                        rect.offsetBy(dx: origin.x, dy: origin.y),
                        radius: self.inlineCodeFontSize(forGlyphRange: glyphs) * DocumentTypography.inlineCodeRadiusRatio)
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
                let rect = taskMarkerRect(at: marker)?.offsetBy(dx: origin.x, dy: origin.y)
            {
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

    func quoteBarDrawingRects(
        forGlyphRange glyphsToShow: NSRange, at origin: CGPoint,
        trailingEmptyBar: CGRect? = nil
    ) -> [CGRect] {
        guard let storage = textStorage else { return [] }
        var rects: [CGRect] = []
        storage.enumerateAttribute(.weaveQuote, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard value as? Bool == true else { return }
            var drawnCharacters = range
            if drawnCharacters.length > 1,
                (storage.string as NSString).substring(with: NSRange(location: NSMaxRange(drawnCharacters) - 1, length: 1)) == "\n"
            {
                // A paragraph's terminating newline keeps its quote semantics
                // for serialization, but its TextKit glyph range reaches into
                // the following line. The active trailing empty quote is drawn
                // separately from typing attributes below.
                drawnCharacters.length -= 1
            }
            let glyphs = self.glyphRange(forCharacterRange: drawnCharacters, actualCharacterRange: nil)
            guard NSIntersectionRange(glyphs, glyphsToShow).length > 0,
                let container = self.textContainer(forGlyphAt: glyphs.location, effectiveRange: nil)
            else { return }
            rects.append(
                self.quoteBarRect(forGlyphRange: glyphs, in: container)
                    .offsetBy(dx: origin.x, dy: origin.y))
        }
        if let trailingEmptyBar,
            storage.length > 0,
            storage.string.hasSuffix("\n"),
            storage.attribute(.weaveQuote, at: storage.length - 1, effectiveRange: nil) as? Bool == true,
            !rects.isEmpty
        {
            rects[rects.count - 1] = rects[rects.count - 1].union(trailingEmptyBar)
        }
        return rects
    }

    @discardableResult
    func drawQuoteBars(
        forGlyphRange glyphsToShow: NSRange, at origin: CGPoint,
        trailingEmptyBar: CGRect? = nil
    ) -> Bool {
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
            storage.attribute(.weaveParagraphStyle, at: character, effectiveRange: nil) as? String == "task"
        else { return nil }
        let reference = character
        guard let font = storage.attribute(.font, at: reference, effectiveRange: nil) as? PlatformFont else { return nil }
        let glyphs = glyphRange(forCharacterRange: NSRange(location: reference, length: 1), actualCharacterRange: nil)
        guard glyphs.length > 0,
            textContainer(forGlyphAt: glyphs.location, effectiveRange: nil) != nil
        else { return nil }
        let fragment = lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
        let textX = fragment.minX + location(forGlyphAt: glyphs.location).x
        let baseline = fragment.minY + self.location(forGlyphAt: glyphs.location).y
        let ascent = CTFontGetAscent(font as CTFont)
        let descent = CTFontGetDescent(font as CTFont)
        return taskMarkerRect(textX: textX, baseline: baseline, font: font, ascent: ascent, descent: descent)
    }

    func emptyTaskMarkerRect(
        at insertion: Int, font: PlatformFont, quoted: Bool,
        in container: NSTextContainer
    ) -> CGRect {
        let fragment: CGRect
        if let storage = textStorage, storage.length > 0, insertion < storage.length {
            fragment = lineFragmentRect(forGlyphAt: glyphIndexForCharacter(at: insertion), effectiveRange: nil)
        } else {
            fragment = extraLineFragmentRect
        }
        let lineHeight = NativeTextAttributes.stableLineHeight(for: font)
        #if os(macOS)
            let baseline = fragment.minY + stableBaselineOffset(fontSize: font.pointSize, lineHeight: lineHeight)
        #else
            let baseline = fragment.minY + max(0, (lineHeight - font.lineHeight) / 2) + font.ascender
        #endif
        let textX =
            fragment.minX + DocumentTypography.listIndent
            + (quoted ? DocumentTypography.quoteIndent : 0)
        return taskMarkerRect(
            textX: textX,
            baseline: baseline,
            font: font,
            ascent: CTFontGetAscent(font as CTFont),
            descent: CTFontGetDescent(font as CTFont)
        )
    }

    private func taskMarkerRect(
        textX: CGFloat, baseline: CGFloat, font: PlatformFont,
        ascent: CGFloat, descent: CGFloat
    ) -> CGRect {
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
            storage.attribute(.weaveTaskChecked, at: marker, effectiveRange: nil) is Bool
        else { return nil }
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

    func drawTaskMarker(checked: Bool, hovered: Bool, in rect: CGRect) {
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
            guard let image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)?.withSymbolConfiguration(configuration)
            else { return }
            let checkSize = rect.height * DocumentTypography.taskCheckScale
            let ratio = image.size.width / max(1, image.size.height)
            let horizontalOffset = rect.height * DocumentTypography.taskCheckHorizontalOffsetRatio
            let target = CGRect(
                x: rect.midX - checkSize * ratio / 2 + horizontalOffset, y: rect.midY - checkSize / 2, width: checkSize * ratio,
                height: checkSize)
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
            let target = CGRect(
                x: rect.midX - checkSize * ratio / 2 + horizontalOffset, y: rect.midY - checkSize / 2, width: checkSize * ratio,
                height: checkSize)
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
            self.enumerateEnclosingRects(
                forGlyphRange: visible, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: container
            ) { rect, _ in
                var background = CGRect(
                    x: rect.minX, y: baseline - above - size * DocumentTypography.inlineCodeBackgroundRiseRatio, width: rect.width,
                    height: above + below)
                let last = (storage.string as NSString).rangeOfComposedCharacterSequence(at: NSMaxRange(characters) - 1).location
                if storage.attribute(.weaveInlineSpacing, at: last, effectiveRange: nil) != nil {
                    let original = storage.attribute(.weaveInlineSpacing, at: last, effectiveRange: nil) as? CGFloat ?? 0
                    let current = storage.attribute(.kern, at: last, effectiveRange: nil) as? CGFloat ?? original
                    background.size.width = max(0, background.width - (current - original))
                }
                result.append(
                    background.insetBy(
                        dx: -size * DocumentTypography.inlineCodePaddingRatio, dy: -size * DocumentTypography.inlineCodeVerticalPaddingRatio
                    ))
            }
        }
        return result
    }

    func fill(_ rect: CGRect, radius: CGFloat) {
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

    private static func paragraphRegion(in text: NSAttributedString, around affected: NSRange?) -> NSRange {
        let whole = NSRange(location: 0, length: text.length)
        guard let affected, text.length > 0 else { return whole }
        let source = text.string as NSString
        let lowerProbe = max(0, min(text.length - 1, affected.location - 1))
        let upperProbe = max(lowerProbe, min(text.length - 1, NSMaxRange(affected)))
        let lower = source.paragraphRange(for: NSRange(location: lowerProbe, length: 0)).location
        let upper = NSMaxRange(source.paragraphRange(for: NSRange(location: upperProbe, length: 0)))
        return NSRange(location: lower, length: upper - lower)
    }

    private static func layoutInlineCode(_ text: NSMutableAttributedString, in region: NSRange) {
        text.enumerateAttribute(.weaveInlineSpacing, in: region) { previous, range, _ in
            guard let previous = previous as? CGFloat else { return }
            if previous == 0 { text.removeAttribute(.kern, range: range) } else { text.addAttribute(.kern, value: previous, range: range) }
        }
        text.removeAttribute(.weaveInlineSpacing, range: region)
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
            CGFloat(
                CTLineGetTypographicBounds(
                    CTLineCreateWithAttributedString(text.attributedSubstring(from: NSRange(location: index, length: 1))), nil, nil, nil))
        }
        text.enumerateAttribute(.weaveCodeStyle, in: region) { value, clippedRange, _ in
            guard value as? String == "inline", clippedRange.length > 0 else { return }
            var range = NSRange()
            _ = text.attribute(
                .weaveCodeStyle, at: clippedRange.location, longestEffectiveRange: &range,
                in: NSRange(location: 0, length: text.length))
            let size =
                (text.attribute(.font, at: range.location, effectiveRange: nil) as? PlatformFont)?.pointSize ?? DocumentTypography.bodySize
                * DocumentTypography.inlineCodeScale
            if range.location > 0 {
                let previous = source.rangeOfComposedCharacterSequence(at: range.location - 1)
                if source.substring(with: previous) == " " {
                    // Count the existing space toward the visual gap. Multiple
                    // spaces, tabs and line breaks retain their authored spacing.
                    if previous.location > 0 {
                        let neighbor = source.rangeOfComposedCharacterSequence(at: previous.location - 1)
                        let neighborSize =
                            (text.attribute(.font, at: neighbor.location, effectiveRange: nil) as? PlatformFont)?.pointSize ?? size
                        let target =
                            isInline(at: neighbor.location)
                            ? (size + neighborSize) * (DocumentTypography.inlineCodePaddingRatio + DocumentTypography.inlineCodeMarginRatio)
                            : gap(beside: neighbor, size: size)
                        addGap(at: previous.location, amount: max(0, target - spaceWidth(at: previous.location)))
                    }
                } else {
                    addGap(at: previous.location, amount: gap(beside: previous, size: size))
                }
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
                } else {
                    addGap(at: last, amount: gap(beside: next, size: size))
                }
            }
        }
    }

    static func layoutParagraphs(_ text: NSMutableAttributedString, around affected: NSRange? = nil) {
        let region = paragraphRegion(in: text, around: affected)
        layoutInlineCode(text, in: region)
        text.enumerateAttribute(.weaveQuoteColor, in: region) { value, range, _ in
            guard value != nil else { return }
            #if os(macOS)
                text.addAttribute(.foregroundColor, value: NSColor.textColor, range: range)
            #else
                text.addAttribute(.foregroundColor, value: UIColor.label, range: range)
            #endif
        }
        text.removeAttribute(.weaveQuoteColor, range: region)
        let source = text.string as NSString
        var location = region.location
        while location < NSMaxRange(region) {
            let range = source.paragraphRange(for: NSRange(location: location, length: 0))
            let content = source.substring(with: range).trimmingCharacters(in: .newlines)
            var font = text.attribute(.font, at: location, effectiveRange: nil) as? PlatformFont
            if text.attribute(.weaveCodeStyle, at: location, effectiveRange: nil) as? String == "inline", let inlineFont = font {
                font =
                    CTFontCreateCopyWithAttributes(
                        inlineFont as CTFont, inlineFont.pointSize / DocumentTypography.inlineCodeScale, nil, nil) as PlatformFont
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
            let quoted =
                text.attribute(.weaveQuote, at: location, effectiveRange: nil) as? Bool == true
                || role == "quote" || content.hasPrefix("│ ")
            if let heading = DocumentTypography.heading(for: role) {
                paragraph.lineSpacing = heading.lineSpacing
                paragraph.paragraphSpacingBefore = location == 0 ? 0 : heading.before
                paragraph.paragraphSpacing = heading.after
            }
            if content.trimmingCharacters(in: .whitespaces).hasPrefix("• ") || role == "task"
                || content.range(of: #"^\d+\. "#, options: .regularExpression) != nil
            {
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
                let next =
                    NSMaxRange(range) < text.length
                    ? text.attribute(.weaveCodeStyle, at: NSMaxRange(range), effectiveRange: nil) as? String : nil
                paragraph.maximumLineHeight = 0
                paragraph.lineSpacing = DocumentTypography.codeLineSpacing
                paragraph.firstLineHeadIndent = DocumentTypography.codeInset
                paragraph.headIndent = DocumentTypography.codeInset
                paragraph.tailIndent = -DocumentTypography.codeInset
                paragraph.paragraphSpacingBefore = previous == code ? 0 : DocumentTypography.codeBefore
                paragraph.paragraphSpacing = next == code ? 0 : DocumentTypography.codeAfter
            }
            if quoted {
                let structured =
                    role == "task" || role == "bullet" || role == "numbered" || role == "code"
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
                let inlineFont = text.attribute(.font, at: location, effectiveRange: nil) as? PlatformFont
            {
                // A leading inline span has no preceding character to carry its
                // inset. Reserve it through native paragraph layout instead.
                paragraph.firstLineHeadIndent +=
                    inlineFont.pointSize * (DocumentTypography.inlineCodePaddingRatio + DocumentTypography.inlineCodeMarginRatio)
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
            let font =
                role.hasPrefix("heading:") || run[CodeStyleAttribute.self] == "inline"
                ? DocumentTypography.font(
                    for: role, emphasis: emphasis, inlineCode: run[CodeStyleAttribute.self] == "inline", context: context)
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
                let legacyBlockStart = blockStart ?? location
                blockStart = legacyBlockStart
                result.addAttribute(.weaveCodeStyle, value: "block:legacy-\(legacyBlockStart)", range: paragraph)
            } else {
                blockStart = nil
            }
            location = NSMaxRange(paragraph)
        }
        layoutParagraphs(result)
        highlightCode(result)
        return result
    }

    static func highlightCode(_ text: NSMutableAttributedString, around affected: NSRange? = nil) {
        var region = paragraphRegion(in: text, around: affected)
        let whole = NSRange(location: 0, length: text.length)
        if region.length > 0 {
            text.enumerateAttribute(.weaveCodeStyle, in: region) { value, clippedRange, _ in
                guard let id = value as? String, id.hasPrefix("block:") || id == "inline" else { return }
                var effective = NSRange()
                _ = text.attribute(.weaveCodeStyle, at: clippedRange.location, longestEffectiveRange: &effective, in: whole)
                region = NSUnionRange(region, effective)
            }
        }
        #if os(macOS)
            let base = NSColor.textColor
            let inlineColor = NSColor.textColor
        #else
            let base = UIColor.label
            let inlineColor = UIColor.label
        #endif
        text.enumerateAttribute(.weaveSyntaxColor, in: region) { marker, range, _ in
            if marker != nil { text.addAttribute(.foregroundColor, value: base, range: range) }
        }
        text.removeAttribute(.weaveSyntaxColor, range: region)
        text.enumerateAttribute(.weaveCodeStyle, in: region) { value, clippedRange, _ in
            var range = NSRange()
            _ = text.attribute(.weaveCodeStyle, at: clippedRange.location, longestEffectiveRange: &range, in: whole)
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
                text.addAttributes(
                    [.foregroundColor: color, .weaveSyntaxColor: true],
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
                let table = try? JSONDecoder().decode(TableData.self, from: encoded)
            {
                result[range][TableAttribute.self] = table
            }
            if let emphasis = attributes[.weaveInlineEmphasis] as? Int { result[range][InlineEmphasisAttribute.self] = emphasis }
            if let language = attributes[.weaveCodeLanguage] as? String { result[range][CodeLanguageAttribute.self] = language }
            if let style = attributes[.weaveParagraphStyle] as? String { result[range][ParagraphStyleAttribute.self] = style }
            if attributes[.weaveQuote] as? Bool == true { result[range][QuoteAttribute.self] = true }
            if let checked = attributes[.weaveTaskChecked] as? Bool { result[range][TaskStateAttribute.self] = checked }
            if let style = attributes[.weaveCodeStyle] as? String { result[range][CodeStyleAttribute.self] = style }
            if let font = attributes[.font] as? PlatformFont { result[range].font = Font(storedFont(font as CTFont)) }
            if let link = attributes[.link] as? URL {
                result[range].link = link
            } else if let link = attributes[.link] as? String {
                result[range].link = URL(string: link)
            }
            if let style = attributes[.underlineStyle] as? Int, style != 0 { result[range].underlineStyle = .single }
            if let style = attributes[.strikethroughStyle] as? Int, style != 0 { result[range].strikethroughStyle = .single }
            #if os(macOS)
                if let color = attributes[.foregroundColor] as? NSColor, color != .textColor, color != .clear,
                    attributes[.weaveSyntaxColor] == nil, attributes[.weaveQuoteColor] == nil
                {
                    result[range].foregroundColor = Color(nsColor: color)
                }
                if let color = attributes[.backgroundColor] as? NSColor { result[range].backgroundColor = Color(nsColor: color) }
            #else
                if let color = attributes[.foregroundColor] as? UIColor, color != .label, color != .clear,
                    attributes[.weaveSyntaxColor] == nil, attributes[.weaveQuoteColor] == nil
                {
                    result[range].foregroundColor = Color(uiColor: color)
                }
                if let color = attributes[.backgroundColor] as? UIColor { result[range].backgroundColor = Color(uiColor: color) }
            #endif
        }
        return result
    }
}
