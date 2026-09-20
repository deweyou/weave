import SwiftUI
import Testing

@testable import Weave

#if os(macOS)
    import AppKit

    struct ReadingLayoutTests {
        @Test @MainActor func taskMarkersUseScaledSquareGeometryAndKeepMarkdownSemantics() throws {
            let context = EnvironmentValues().fontResolutionContext
            let native = NativeTextAttributes.native(MarkdownFormatting.render("- [ ] Open\n- [x] Done"), context: context)
            #expect(native.string == "Open\nDone")
            let storage = NSTextStorage(attributedString: native)
            let layout = CodeLayoutManager()
            let container = NSTextContainer(size: CGSize(width: 500, height: 10_000))
            storage.addLayoutManager(layout)
            layout.addTextContainer(container)
            layout.ensureLayout(for: container)
            for marker in [0, 5] {
                let font = try #require(storage.attribute(.font, at: marker, effectiveRange: nil) as? NSFont)
                let rect = try #require(layout.taskMarkerRect(at: marker))
                let textGlyph = layout.glyphRange(forCharacterRange: NSRange(location: marker, length: 1), actualCharacterRange: nil)
                let fragment = layout.lineFragmentRect(forGlyphAt: textGlyph.location, effectiveRange: nil)
                let textOrigin = fragment.minX + layout.location(forGlyphAt: textGlyph.location).x
                let baseline = fragment.minY + layout.location(forGlyphAt: textGlyph.location).y
                let expectedCenter = baseline + (CTFontGetDescent(font) - CTFontGetAscent(font)) / 2
                #expect(abs(rect.width - rect.height) < 0.01)
                #expect(abs(rect.height / font.pointSize - DocumentTypography.taskIconScale) < 0.01)
                #expect(abs(textOrigin - rect.maxX - font.pointSize * DocumentTypography.taskTextGapRatio) < 0.01)
                #expect(abs(rect.midY - expectedCenter) < 0.01)
                #expect(layout.taskMarkerCharacter(at: CGPoint(x: rect.midX, y: rect.midY), in: container) == marker)
                let hitRect = try #require(layout.taskMarkerHitRect(at: marker))
                #expect(hitRect.width >= DocumentTypography.taskIconHitSize)
                #expect(layout.taskMarkerCharacter(at: CGPoint(x: hitRect.minX + 0.1, y: hitRect.midY), in: container) == marker)
                #expect(layout.taskMarkerCharacter(at: CGPoint(x: hitRect.maxX - 0.1, y: hitRect.midY), in: container) == marker)
                #expect(layout.taskMarkerCharacter(at: CGPoint(x: hitRect.maxX + 0.1, y: hitRect.midY), in: container) == nil)
                #expect(abs(textOrigin - container.lineFragmentPadding - DocumentTypography.listIndent) < 0.5)
                #expect(rect.maxX < textOrigin)
                #expect(layout.taskMarkerAdjacent(to: marker) == marker)
                #expect(layout.taskMarkerAdjacent(to: marker) == marker)
                #expect(layout.taskMarkerAdjacent(to: marker + 1) == nil)
            }
            let rich = NativeTextAttributes.rich(native)
            #expect(MarkdownFormatting.serialize(rich, context: context) == "- [ ] Open\n- [x] Done")
        }

        @Test @MainActor func taskSelectionContainsOnlyContentAndBlankLineHighlightsCanBeRemoved() throws {
            let context = EnvironmentValues().fontResolutionContext
            let rich = MarkdownFormatting.render("\n\n- [ ] Task\n")
            let native = NativeTextAttributes.native(rich, context: context)
            #expect(native.string == "\n\nTask\n")
            #expect(!native.string.contains("☐"))
            let storage = NSTextStorage(attributedString: native)
            let layout = CodeLayoutManager()
            let container = NSTextContainer(size: CGSize(width: 500, height: 10_000))
            storage.addLayoutManager(layout)
            layout.addTextContainer(container)
            layout.ensureLayout(for: container)
            let cleanup = layout.selectionCleanupRects(for: NSRange(location: 0, length: storage.length))
            #expect(cleanup.count == 2)
            let taskRange = (storage.string as NSString).range(of: "Task")
            let taskGlyphs = layout.glyphRange(forCharacterRange: taskRange, actualCharacterRange: nil)
            let taskLine = layout.lineFragmentRect(forGlyphAt: taskGlyphs.location, effectiveRange: nil)
            #expect(cleanup.allSatisfy { !$0.intersects(taskLine) })
        }

        @Test @MainActor func quoteDecorationDoesNotAddTextWidthOnTopOfParagraphIndent() throws {
            let context = EnvironmentValues().fontResolutionContext
            let native = NativeTextAttributes.native(MarkdownFormatting.render("> Quote"), context: context)
            #expect(native.string == "Quote")
            #expect(native.attribute(.weaveQuote, at: 0, effectiveRange: nil) as? Bool == true)
            #expect(native.attribute(.weaveQuoteColor, at: 0, effectiveRange: nil) as? Bool == true)
            #expect(native.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == NSColor.secondaryLabelColor)
            let storage = NSTextStorage(attributedString: native)
            let layout = CodeLayoutManager()
            let container = NSTextContainer(size: CGSize(width: 500, height: 10_000))
            storage.addLayoutManager(layout)
            layout.addTextContainer(container)
            layout.ensureLayout(for: container)

            let textGlyph = layout.glyphRange(forCharacterRange: NSRange(location: 0, length: 1), actualCharacterRange: nil)
            let fragment = layout.lineFragmentRect(forGlyphAt: textGlyph.location, effectiveRange: nil)
            let used = layout.lineFragmentUsedRect(forGlyphAt: textGlyph.location, effectiveRange: nil)
            let textOrigin = fragment.minX + layout.location(forGlyphAt: textGlyph.location).x
            #expect(abs(textOrigin - container.lineFragmentPadding - DocumentTypography.quoteIndent) < 0.5)
            let quoteGlyphs = layout.glyphRange(forCharacterRange: NSRange(location: 0, length: native.length), actualCharacterRange: nil)
            let bar = layout.quoteBarRect(forGlyphRange: quoteGlyphs, in: container)
            #expect(bar.minY < used.minY)
            #expect(bar.maxY > used.maxY)
            #expect(abs(bar.minX - container.lineFragmentPadding) < 0.01)
            let expectedTop = DocumentTypography.quoteBarVerticalOvershootRatio + DocumentTypography.quoteBarOpticalRiseRatio
            let expectedBottom = DocumentTypography.quoteBarVerticalOvershootRatio - DocumentTypography.quoteBarOpticalRiseRatio
            #expect(abs((used.minY - bar.minY) / DocumentTypography.bodySize - expectedTop) < 0.01)
            #expect(abs((bar.maxY - used.maxY) / DocumentTypography.bodySize - expectedBottom) < 0.01)
            let rich = NativeTextAttributes.rich(storage)
            #expect(rich[rich.startIndex..<rich.endIndex][QuoteAttribute.self] == true)
            #expect(rich.runs.allSatisfy { $0.foregroundColor == nil })
            #expect(MarkdownFormatting.serialize(rich, context: context) == "> Quote")
        }

        @Test @MainActor func quoteBarDoesNotEnterFollowingEmptyBodyCaretRow() throws {
            let context = EnvironmentValues().fontResolutionContext
            let native = NativeTextAttributes.native(MarkdownFormatting.render("> Quote\n\n\nBody"), context: context)
            let storage = NSTextStorage(attributedString: native)
            let layout = CodeLayoutManager()
            let container = NSTextContainer(size: CGSize(width: 500, height: 10_000))
            storage.addLayoutManager(layout)
            layout.addTextContainer(container)
            layout.ensureLayout(for: container)

            var foundQuoteRange: NSRange?
            storage.enumerateAttribute(.weaveQuote, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
                if value as? Bool == true, foundQuoteRange == nil { foundQuoteRange = range }
            }
            let quoteRange = try #require(foundQuoteRange)
            #expect(NSMaxRange(quoteRange) < storage.length)
            let bodyIndex = NSMaxRange(quoteRange)
            #expect(storage.attribute(.weaveParagraphStyle, at: bodyIndex, effectiveRange: nil) as? String == "body")
            let quoteGlyphs = layout.glyphRange(forCharacterRange: quoteRange, actualCharacterRange: nil)
            let bodyGlyphs = layout.glyphRange(forCharacterRange: NSRange(location: bodyIndex, length: 1), actualCharacterRange: nil)
            let bar = layout.quoteBarRect(forGlyphRange: quoteGlyphs, in: container)
            let quoteLine = layout.lineFragmentRect(forGlyphAt: quoteGlyphs.location, effectiveRange: nil)
            let quoteStyle = try #require(
                storage.attribute(.paragraphStyle, at: quoteRange.location, effectiveRange: nil) as? NSParagraphStyle)
            let bodyLine = layout.lineFragmentRect(forGlyphAt: bodyGlyphs.location, effectiveRange: nil)
            let expectedBottom = DocumentTypography.quoteBarTerminalBottomOvershootRatio - DocumentTypography.quoteBarOpticalRiseRatio
            #expect(abs((bar.maxY - quoteLine.minY - quoteStyle.maximumLineHeight) / DocumentTypography.bodySize - expectedBottom) < 0.01)
            #expect(bar.maxY <= bodyLine.minY)
        }

        @Test @MainActor func emptyQuoteHasAVisibleBarWithoutPlaceholderText() {
            let storage = NSTextStorage()
            let layout = CodeLayoutManager()
            let container = NSTextContainer(size: CGSize(width: 500, height: 10_000))
            storage.addLayoutManager(layout)
            layout.addTextContainer(container)
            layout.ensureLayout(for: container)

            let font = NSFont.systemFont(ofSize: DocumentTypography.bodySize)
            let bar = layout.emptyQuoteBarRect(font: font, in: container)
            #expect(storage.string.isEmpty)
            #expect(bar.width == 2)
            #expect(
                abs(
                    bar.height
                        - (NativeTextAttributes.stableLineHeight(for: font)
                            + DocumentTypography.bodySize * DocumentTypography.quoteBarVerticalOvershootRatio * 2)) < 0.01)
            #expect(abs(bar.minX - container.lineFragmentPadding) < 0.01)
        }

        @Test @MainActor func quoteBarUsesTheSameFixedLineHeightForDigitsAndChinese() {
            func bar(for source: String) -> CGRect {
                let native = NativeTextAttributes.native(
                    MarkdownFormatting.render("> " + source), context: EnvironmentValues().fontResolutionContext)
                let storage = NSTextStorage(attributedString: native)
                let layout = CodeLayoutManager()
                let container = NSTextContainer(size: CGSize(width: 500, height: 10_000))
                storage.addLayoutManager(layout)
                layout.addTextContainer(container)
                layout.ensureLayout(for: container)
                return layout.quoteBarRect(forGlyphRange: NSRange(location: 0, length: layout.numberOfGlyphs), in: container)
            }

            #expect(abs(bar(for: "12312312").height - bar(for: "引用文本").height) < 0.01)
        }

        @Test @MainActor func macEditorDrawsEmptyAndSingleDigitQuoteBarsAtTheSameHeight() throws {
            let native = NativeTextAttributes.native(
                MarkdownFormatting.render("> 1"),
                context: EnvironmentValues().fontResolutionContext
            )
            let quoteAttributes = native.attributes(at: 0, effectiveRange: nil)
            let storage = NSTextStorage()
            let layout = CodeLayoutManager()
            let container = NSTextContainer(size: CGSize(width: 500, height: 10_000))
            storage.addLayoutManager(layout)
            layout.addTextContainer(container)
            let view = ReadingMacTextView(
                frame: CGRect(x: 0, y: 0, width: 500, height: 400),
                textContainer: container
            )
            let window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = view
            view.typingAttributes = quoteAttributes
            view.setSelectedRange(NSRange(location: 0, length: 0))
            layout.ensureLayout(for: container)
            let empty = try #require(view.emptyQuoteBarDrawingRect())

            storage.setAttributedString(native)
            view.typingAttributes = quoteAttributes
            view.setSelectedRange(NSRange(location: storage.length, length: 0))
            layout.ensureLayout(for: container)
            let glyphs = layout.glyphRange(
                forCharacterRange: NSRange(location: 0, length: storage.length),
                actualCharacterRange: nil
            )
            let filled = layout.quoteBarRect(forGlyphRange: glyphs, in: container).offsetBy(
                dx: view.textContainerOrigin.x,
                dy: view.textContainerOrigin.y
            )

            #expect(abs(filled.minY - empty.minY) < 0.01)
            #expect(abs(filled.maxY - empty.maxY) < 0.01)
        }

        @Test @MainActor func emptyTerminalQuoteUsesTheSameBarGeometryBeforeBodyText() throws {
            func layout(for markdown: String) -> (NSTextStorage, CodeLayoutManager, NSTextContainer) {
                let native = NativeTextAttributes.native(
                    MarkdownFormatting.render(markdown),
                    context: EnvironmentValues().fontResolutionContext
                )
                let storage = NSTextStorage(attributedString: native)
                let layout = CodeLayoutManager()
                let container = NSTextContainer(size: CGSize(width: 500, height: 10_000))
                storage.addLayoutManager(layout)
                layout.addTextContainer(container)
                layout.ensureLayout(for: container)
                return (storage, layout, container)
            }

            let (filledStorage, filledLayout, filledContainer) = layout(for: "> 1\n\nBody")
            var quoteRange = NSRange(location: NSNotFound, length: 0)
            filledStorage.enumerateAttribute(.weaveQuote, in: NSRange(location: 0, length: filledStorage.length)) { value, range, stop in
                if value as? Bool == true {
                    quoteRange = range
                    stop.pointee = true
                }
            }
            let range = try #require(quoteRange.location != NSNotFound ? quoteRange : nil)
            let filled = filledLayout.quoteBarRect(
                forGlyphRange: filledLayout.glyphRange(forCharacterRange: range, actualCharacterRange: nil),
                in: filledContainer
            )

            let (emptyStorage, emptyLayout, emptyContainer) = layout(for: "\nBody")
            let font = try #require(filledStorage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont)
            let empty = emptyLayout.emptyQuoteBarRect(at: 0, font: font, in: emptyContainer)

            #expect(emptyStorage.string.hasPrefix("\n"))
            #expect(abs(filled.minY - empty.minY) < 0.01)
            #expect(abs(filled.maxY - empty.maxY) < 0.01)
        }

        @Test @MainActor func emptyQuoteBarCanUseAnEmptyParagraphInsideANonemptyDocument() {
            let storage = NSTextStorage(
                attributedString: NativeTextAttributes.native(
                    MarkdownFormatting.render("Before\n\n\nAfter"),
                    context: EnvironmentValues().fontResolutionContext
                ))
            let layout = CodeLayoutManager()
            let container = NSTextContainer(size: CGSize(width: 500, height: 10_000))
            storage.addLayoutManager(layout)
            layout.addTextContainer(container)
            layout.ensureLayout(for: container)
            let blankBreaks = (storage.string as NSString).range(of: "\n\n")
            #expect(blankBreaks.location != NSNotFound)
            let insertion = blankBreaks.location + 1
            let font =
                storage.attribute(.font, at: insertion, effectiveRange: nil) as? NSFont
                ?? .systemFont(ofSize: DocumentTypography.bodySize)
            let bar = layout.emptyQuoteBarRect(at: insertion, font: font, in: container)
            let glyph = layout.glyphIndexForCharacter(at: insertion)
            let fragment = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)

            #expect(
                abs(
                    bar.minY
                        - (fragment.minY
                            - font.pointSize
                            * (DocumentTypography.quoteBarVerticalOvershootRatio + DocumentTypography.quoteBarOpticalRiseRatio))) < 0.01)
        }

        @Test @MainActor func leadingInlineCodeReservesItsScaledLeftMargin() throws {
            for prefix in ["", "# "] {
                let storage = NSTextStorage(
                    attributedString: NativeTextAttributes.native(
                        MarkdownFormatting.render(prefix + "`value` after"), context: EnvironmentValues().fontResolutionContext))
                let layout = CodeLayoutManager()
                let container = NSTextContainer(size: CGSize(width: 500, height: 10_000))
                storage.addLayoutManager(layout)
                layout.addTextContainer(container)
                layout.ensureLayout(for: container)
                let size = try #require(storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont).pointSize
                let glyphs = layout.glyphRange(forCharacterRange: NSRange(location: 0, length: 5), actualCharacterRange: nil)
                let rect = try #require(layout.inlineCodeBackgroundRects(forGlyphRange: glyphs, in: container).first)
                #expect(abs(rect.minX - container.lineFragmentPadding - size * 0.3) < 0.5)
            }
        }

        @Test @MainActor func inlineCodeScalesWithEveryHeadingAndSurvivesRoundTrip() throws {
            let context = EnvironmentValues().fontResolutionContext
            for level in 0...6 {
                let prefix = level == 0 ? "" : String(repeating: "#", count: level) + " "
                let role = level == 0 ? "body" : "heading:\(level)"
                let expectedSize =
                    DocumentTypography.bodySize * (DocumentTypography.heading(for: role)?.ratio ?? 1) * DocumentTypography.inlineCodeScale
                var rich = MarkdownFormatting.render(prefix + "Before`value`after")
                for _ in 0..<3 {
                    let native = NativeTextAttributes.native(rich, context: context)
                    let range = (native.string as NSString).range(of: "value")
                    let font = try #require(native.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont)
                    #expect(abs(font.pointSize - expectedSize) < 0.01)
                    let gap = try #require(native.attribute(.kern, at: NSMaxRange(range) - 1, effectiveRange: nil) as? CGFloat)
                    #expect(abs(gap / font.pointSize - 0.8) < 0.01)
                    let storage = NSTextStorage(attributedString: native)
                    let layout = CodeLayoutManager()
                    let container = NSTextContainer(size: CGSize(width: 800, height: 10_000))
                    storage.addLayoutManager(layout)
                    layout.addTextContainer(container)
                    layout.ensureLayout(for: container)
                    let glyphs = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                    let background = try #require(layout.inlineCodeBackgroundRects(forGlyphRange: glyphs, in: container).first)
                    #expect(background.height / expectedSize > 0.9)
                    #expect(background.height / expectedSize < 1.5)
                    rich = NativeTextAttributes.rich(native)
                    #expect(rich[rich.range(of: "value")!][ParagraphStyleAttribute.self] == role)
                }
            }
        }

        @Test @MainActor func inlineCodeColorFollowsAppearanceWithoutReopeningDocument() throws {
            let light = try #require(NSAppearance(named: .aqua))
            let dark = try #require(NSAppearance(named: .darkAqua))
            var native = NSAttributedString()
            light.performAsCurrentDrawingAppearance {
                native = NativeTextAttributes.native(
                    MarkdownFormatting.render("`let value = 1`"), context: EnvironmentValues().fontResolutionContext)
            }
            let color = try #require(native.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)
            var lightWhite: CGFloat = 0
            var darkWhite: CGFloat = 0
            light.performAsCurrentDrawingAppearance { lightWhite = color.usingColorSpace(.deviceRGB)!.redComponent }
            dark.performAsCurrentDrawingAppearance { darkWhite = color.usingColorSpace(.deviceRGB)!.redComponent }
            #expect(lightWhite < 0.3)
            #expect(darkWhite > 0.7)
            #expect(NativeTextAttributes.rich(native).runs.first?.foregroundColor == nil)
        }

        @Test @MainActor func inlineBackgroundUsesCodeMetricsInsideTallText() throws {
            let native = NativeTextAttributes.native(
                MarkdownFormatting.render("# Heading `let counthg = 42`"), context: EnvironmentValues().fontResolutionContext)
            let storage = NSTextStorage(attributedString: native)
            let layout = CodeLayoutManager()
            let container = NSTextContainer(size: CGSize(width: 500, height: 10_000))
            storage.addLayoutManager(layout)
            layout.addTextContainer(container)
            layout.ensureLayout(for: container)
            let range = (native.string as NSString).range(of: "let counthg = 42")
            let glyphs = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let fragment = layout.lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
            let baseline = fragment.minY + layout.location(forGlyphAt: glyphs.location).y
            let rect = try #require(layout.inlineCodeBackgroundRects(forGlyphRange: glyphs, in: container).first)
            #expect(rect.height < fragment.height)
            #expect(rect.minY < baseline && rect.maxY > baseline)
            #expect(layout.lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil) == fragment)
        }

        @Test @MainActor func inlineCodeSingleSpacesDoNotDoubleBoundaryGaps() {
            var positions: [[CGFloat]] = []
            for source in ["\u{524D}`x`\u{540E}", "\u{524D} `x` \u{540E}"] {
                let native = NativeTextAttributes.native(
                    MarkdownFormatting.render(source), context: EnvironmentValues().fontResolutionContext)
                let storage = NSTextStorage(attributedString: native)
                let layout = CodeLayoutManager()
                let container = NSTextContainer(size: CGSize(width: 500, height: 10_000))
                storage.addLayoutManager(layout)
                layout.addTextContainer(container)
                layout.ensureLayout(for: container)
                positions.append(
                    ["x", "\u{540E}"].map { word in
                        let index = (native.string as NSString).range(of: word).location
                        return layout.location(forGlyphAt: layout.glyphIndexForCharacter(at: index)).x
                    })
                #expect(native.string == source.replacingOccurrences(of: "`", with: ""))
            }
            #expect(abs(positions[0][0] - positions[1][0]) < 0.5)
            #expect(abs(positions[0][1] - positions[1][1]) < 0.5)
        }

        @Test @MainActor func inlineCodePresentationSurvivesRepeatedEditingWithoutChangingContent() throws {
            let context = EnvironmentValues().fontResolutionContext
            var rich = MarkdownFormatting.render("\u{524D}`let count = 42`\u{540E}")
            let expected = String(rich.characters)
            for _ in 0..<4 {
                let native = NSMutableAttributedString(attributedString: NativeTextAttributes.native(rich, context: context))
                let code = (native.string as NSString).range(of: "let count = 42")
                let font = try #require(native.attribute(.font, at: code.location, effectiveRange: nil) as? NSFont)
                #expect(abs(font.pointSize - 14 * DocumentTypography.inlineCodeScale) < 0.01)
                let before = native.attribute(.kern, at: 0, effectiveRange: nil) as? CGFloat
                let after = native.attribute(.kern, at: NSMaxRange(code) - 1, effectiveRange: nil) as? CGFloat
                NativeTextAttributes.layoutParagraphs(native)
                NativeTextAttributes.layoutParagraphs(native)
                #expect(native.attribute(.kern, at: 0, effectiveRange: nil) as? CGFloat == before)
                #expect(native.attribute(.kern, at: NSMaxRange(code) - 1, effectiveRange: nil) as? CGFloat == after)
                #expect(abs((before ?? 0) - font.pointSize * 0.8) < 0.01)
                #expect(before == after)
                #expect(native.string == expected)
                rich = NativeTextAttributes.rich(native)
                #expect(rich[rich.range(of: "let count = 42")!].runs.first?.foregroundColor == nil)
                #expect(MarkdownFormatting.serialize(rich, context: context).contains("`let count = 42`"))
            }
        }

        @Test @MainActor func clickingEmptyBodyParagraphDoesNotContinuePreviousCode() {
            let context = EnvironmentValues().fontResolutionContext
            let native = NativeTextAttributes.native(MarkdownFormatting.render("```swift\nlet value = 1\n```\n\n\nNext"), context: context)
            let view = ReadingMacTextView(frame: CGRect(x: 0, y: 0, width: 500, height: 400))
            view.textStorage!.setAttributedString(native)
            let paragraph = (native.string as NSString).range(of: "\n\n").location + 1
            view.setSelectedRange(NSRange(location: paragraph, length: 0))
            view.typingAttributes = native.attributes(at: 0, effectiveRange: nil)
            var published = false
            view.didResolveTypingAttributes = { published = true }
            view.resolveEmptyParagraphTypingAttributes()
            #expect(view.typingAttributes[.weaveCodeStyle] == nil)
            #expect(published)
            view.insertText("x", replacementRange: view.selectedRange())
            #expect(view.textStorage!.attribute(.weaveCodeStyle, at: paragraph, effectiveRange: nil) == nil)
        }

        @Test @MainActor func disconnectedCodeSurfacesDoNotOverlap() throws {
            let context = EnvironmentValues().fontResolutionContext
            let code = "let value = 1\nprint(value)"
            let storage = NSTextStorage(attributedString: NativeTextAttributes.native(AttributedString(code + "\n\n\n"), context: context))
            for range in [NSRange(location: 0, length: code.utf16.count), NSRange(location: code.utf16.count + 1, length: 1)] {
                storage.addAttributes([.weaveCodeStyle: "block:repeated", .weaveParagraphStyle: "code"], range: range)
            }
            NativeTextAttributes.layoutParagraphs(storage)
            let layout = CodeLayoutManager()
            let container = NSTextContainer(size: CGSize(width: 500, height: 10_000))
            storage.addLayoutManager(layout)
            layout.addTextContainer(container)
            layout.ensureLayout(for: container)
            var surfaces: [CGRect] = []
            storage.enumerateAttribute(.weaveCodeStyle, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
                guard value != nil else { return }
                surfaces.append(
                    layout.codeBackgroundRect(
                        forGlyphRange: layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil), in: container))
            }
            #expect(surfaces.count == 2)
            #expect(surfaces[0].maxY <= surfaces[1].minY)
        }

        @Test @MainActor func codeSurfaceDoesNotResizeWhenTypingAttributesChange() throws {
            var source = AttributedString("let value = 1\n")
            source.font = .body.monospaced()
            source[CodeStyleAttribute.self] = "block:test"
            source[ParagraphStyleAttribute.self] = "code"
            let context = EnvironmentValues().fontResolutionContext
            let storage = NSTextStorage(attributedString: NativeTextAttributes.native(source, context: context))
            let layout = CodeLayoutManager()
            let container = NSTextContainer(size: CGSize(width: 500, height: 10_000))
            storage.addLayoutManager(layout)
            layout.addTextContainer(container)
            let view = ReadingMacTextView(frame: CGRect(x: 0, y: 0, width: 500, height: 400), textContainer: container)
            layout.ensureLayout(for: container)
            let glyphs = layout.glyphRange(forCharacterRange: NSRange(location: 0, length: storage.length), actualCharacterRange: nil)
            let original = layout.codeBackgroundRect(forGlyphRange: glyphs, in: container)
            for index in [0, storage.length, 3, storage.length] {
                view.setSelectedRange(NSRange(location: index, length: 0))
                for attributes in [
                    storage.attributes(at: 0, effectiveRange: nil),
                    NativeTextAttributes.native(AttributedString("Body"), context: context).attributes(at: 0, effectiveRange: nil),
                ] {
                    view.typingAttributes = attributes
                    layout.ensureLayout(for: container)
                    #expect(layout.codeBackgroundRect(forGlyphRange: glyphs, in: container) == original)
                }
            }
        }

        @Test @MainActor func nativeSelectionExcludesSpacingAndCodeHeader() throws {
            for source in [
                "Body text\n\nNext", "\u{6B63}\u{6587} text\n\nNext", "## Heading\n\nNext", "```swift\nlet value = 1\nlet next = 2\n```",
                "Before\n\n\nNext", "Emoji \u{1F600}\n\nNext",
            ] {
                let storage = NSTextStorage(
                    attributedString: NativeTextAttributes.native(
                        MarkdownFormatting.render(source), context: EnvironmentValues().fontResolutionContext))
                let layout = CodeLayoutManager()
                let container = NSTextContainer(size: CGSize(width: 160, height: 10_000))
                storage.addLayoutManager(layout)
                layout.addTextContainer(container)
                let view = ReadingMacTextView(frame: CGRect(x: 0, y: 0, width: 160, height: 400), textContainer: container)
                let window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
                window.contentView = view
                layout.ensureLayout(for: container)
                layout.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: layout.numberOfGlyphs)) {
                    fragment, used, _, glyphs, _ in
                    let character = layout.characterIndexForGlyph(at: glyphs.location)
                    view.setSelectedRange(NSRange(location: character, length: 0))
                    let caret = view.firstRect(forCharacterRange: NSRange(location: character, length: 0), actualRange: nil)
                    #expect(abs(caret.height - used.height) < 0.5)
                    #expect(used.height >= 17)
                    #expect(used.maxY <= fragment.maxY)
                    layout.enumerateEnclosingRects(
                        forGlyphRange: NSRange(location: glyphs.location, length: 1), withinSelectedGlyphRange: glyphs, in: container
                    ) { rect, _ in
                        #expect(abs(rect.height - used.height) < 0.5)
                        #expect(abs(rect.minY - used.minY) < 0.5)
                    }
                    if source.hasPrefix("```") && glyphs.location == 0 {
                        #expect(used.minY - fragment.minY == CodeLayoutManager.headerHeight)
                        #expect(used.height < CodeLayoutManager.headerHeight)
                    }
                }
            }
        }

        @Test @MainActor func nativeSelectionKeepsAThirdOfLineSpacingAsBreathingRoom() {
            let storage = NSTextStorage(
                attributedString: NativeTextAttributes.native(
                    AttributedString("First\u{2028}Second"), context: EnvironmentValues().fontResolutionContext))
            let layout = CodeLayoutManager()
            let container = NSTextContainer(size: CGSize(width: 500, height: 10_000))
            storage.addLayoutManager(layout)
            layout.addTextContainer(container)
            layout.ensureLayout(for: container)
            let first = layout.lineFragmentUsedRect(forGlyphAt: 0, effectiveRange: nil)
            let firstFragment = layout.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil)
            let excludedSpacing = DocumentTypography.bodyLineSpacing * (1 - DocumentTypography.selectionLineSpacingShare)
            #expect(abs(firstFragment.height - first.height - excludedSpacing) < 0.5)
        }

        @Test @MainActor func nativeEmptyParagraphGeometryMatchesTypedText() throws {
            for (prefix, suffix) in [
                ("", "\nNext"), ("Before\n", "\nNext"), ("Before\u{2028}", "\nNext"), ("", ""), ("Before\n", ""), ("Before\u{2028}", ""),
            ] {
                var rects: [CGRect] = []
                for content in ["", "x", "\u{4E2D}", ""] {
                    let context = EnvironmentValues().fontResolutionContext
                    let storage = NSTextStorage(
                        attributedString: NativeTextAttributes.native(AttributedString(prefix + content + suffix), context: context))
                    let layout = CodeLayoutManager()
                    let container = NSTextContainer(size: CGSize(width: 500, height: 10_000))
                    storage.addLayoutManager(layout)
                    layout.addTextContainer(container)
                    let view = ReadingMacTextView(frame: CGRect(x: 0, y: 0, width: 500, height: 400), textContainer: container)
                    let window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
                    window.contentView = view
                    view.typingAttributes = NativeTextAttributes.native(AttributedString("x"), context: context).attributes(
                        at: 0, effectiveRange: nil)
                    view.setSelectedRange(NSRange(location: prefix.utf16.count, length: 0))
                    layout.ensureLayout(for: container)
                    rects.append(view.firstRect(forCharacterRange: view.selectedRange(), actualRange: nil))
                }
                for rect in rects {
                    // Screen-space maxY is the top. Native final-line font leading
                    // differs slightly between Latin and CJK; the top must not jump.
                    #expect(abs(rect.maxY - rects[0].maxY) < 0.5)
                    #expect(abs(rect.height - rects[0].height) < (suffix.isEmpty ? 1 : 0.5))
                }
            }
        }

        @Test @MainActor func latinAndCJKEditingUseIdenticalCaretAndLineGeometry() {
            var caretRects: [CGRect] = []
            var lineRects: [CGRect] = []
            for content in ["Hello", "Hello\u{6211}"] {
                let context = EnvironmentValues().fontResolutionContext
                let storage = NSTextStorage(attributedString: NativeTextAttributes.native(AttributedString(content), context: context))
                let layout = CodeLayoutManager()
                let container = NSTextContainer(size: CGSize(width: 500, height: 10_000))
                storage.addLayoutManager(layout)
                layout.addTextContainer(container)
                let view = ReadingMacTextView(frame: CGRect(x: 0, y: 0, width: 500, height: 400), textContainer: container)
                let window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
                window.contentView = view
                view.setSelectedRange(NSRange(location: content.utf16.count, length: 0))
                layout.ensureLayout(for: container)
                caretRects.append(view.firstRect(forCharacterRange: view.selectedRange(), actualRange: nil))
                lineRects.append(layout.lineFragmentRect(forGlyphAt: max(0, layout.numberOfGlyphs - 1), effectiveRange: nil))
            }
            #expect(abs(caretRects[0].height - caretRects[1].height) < 0.01)
            #expect(abs(caretRects[0].minY - caretRects[1].minY) < 0.01)
            #expect(abs(lineRects[0].height - lineRects[1].height) < 0.01)
        }

        @Test @MainActor func markedCJKTextKeepsBodyViewportAndLineGeometryStable() throws {
            let context = EnvironmentValues().fontResolutionContext
            let native = NativeTextAttributes.native(
                AttributedString("asdatas\nabdsadsadas\ndasdasdasda\nsddsdas"),
                context: context
            )
            let storage = NSTextStorage(attributedString: native)
            let layout = CodeLayoutManager()
            let container = NSTextContainer(size: CGSize(width: 500, height: CGFloat.greatestFiniteMagnitude))
            storage.addLayoutManager(layout)
            layout.addTextContainer(container)
            let view = ReadingMacTextView(frame: CGRect(x: 0, y: 0, width: 500, height: 320), textContainer: container)
            view.isVerticallyResizable = true
            view.isHorizontallyResizable = false
            view.minSize = NSSize.zero
            view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            let scroll = NSScrollView(frame: CGRect(x: 0, y: 0, width: 500, height: 320))
            scroll.documentView = view
            let window = NSWindow(contentRect: scroll.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = scroll
            view.setSelectedRange(NSRange(location: storage.length, length: 0))
            view.typingAttributes = storage.attributes(at: storage.length - 1, effectiveRange: nil)
            layout.ensureLayout(for: container)

            let beforeOrigin = scroll.contentView.bounds.origin
            let beforeFrame = view.frame
            let beforeGlyph = layout.glyphIndexForCharacter(at: storage.length - 1)
            let beforeLine = layout.lineFragmentRect(forGlyphAt: beforeGlyph, effectiveRange: nil)
            let beforeLocation = layout.location(forGlyphAt: beforeGlyph)
            let beforeBaseline = beforeLine.minY + beforeLocation.y

            view.setMarkedText(
                "在",
                selectedRange: NSRange(location: 1, length: 0),
                replacementRange: NSRange(location: NSNotFound, length: 0)
            )
            layout.ensureLayout(for: container)
            let markedGlyph = layout.glyphIndexForCharacter(at: storage.length - 1)
            let markedLine = layout.lineFragmentRect(forGlyphAt: markedGlyph, effectiveRange: nil)
            let markedLocation = layout.location(forGlyphAt: markedGlyph)
            let markedBaseline = markedLine.minY + markedLocation.y

            #expect(scroll.contentView.bounds.origin == beforeOrigin)
            #expect(view.frame == beforeFrame)
            #expect(abs(markedBaseline - beforeBaseline) < 0.01)

            let committedRange = view.markedRange()
            view.insertText("在", replacementRange: committedRange)
            layout.ensureLayout(for: container)
            let committedGlyph = layout.glyphIndexForCharacter(at: committedRange.location)
            let committedBaseline =
                layout.lineFragmentRect(forGlyphAt: committedGlyph, effectiveRange: nil).minY
                + layout.location(forGlyphAt: committedGlyph).y
            #expect(abs(committedBaseline - beforeBaseline) < 0.01)
        }

        @Test @MainActor func paragraphBreakAddsEightPointsComparedWithLineBreak() {
            func baselineDistance(_ separator: String) -> CGFloat {
                let text = NativeTextAttributes.native(
                    AttributedString("First" + separator + "Second"), context: EnvironmentValues().fontResolutionContext)
                let storage = NSTextStorage(attributedString: text)
                let layout = CodeLayoutManager()
                let container = NSTextContainer(size: CGSize(width: 560, height: 10_000))
                storage.addLayoutManager(layout)
                layout.addTextContainer(container)
                layout.ensureLayout(for: container)
                func baseline(_ word: String) -> CGFloat {
                    let character = (storage.string as NSString).range(of: word).location
                    let glyph = layout.glyphIndexForCharacter(at: character)
                    return layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY + layout.location(forGlyphAt: glyph).y
                }
                return baseline("Second") - baseline("First")
            }
            #expect(abs(baselineDistance("\n") - baselineDistance("\u{2028}") - 8) < 0.5)
        }

        @Test @MainActor func headingHierarchyStaysReadableAndUsesConsistentSpacing() throws {
            let context = EnvironmentValues().fontResolutionContext
            let body = Font.body.resolve(in: context).ctFont
            let bodySize = CTFontGetSize(body) * DocumentTypography.readingScale
            var previous = CGFloat.greatestFiniteMagnitude
            for level in 1...6 {
                let role = "heading:\(level)"
                let font = ParagraphEditing.font(for: role).resolve(in: context).ctFont
                let size = CTFontGetSize(font) * DocumentTypography.readingScale
                #expect(size >= bodySize - 0.01)
                #expect(size <= previous + 0.01)
                previous = size
                let native = NativeTextAttributes.native(
                    MarkdownFormatting.render("Body\n" + String(repeating: "#", count: level) + " Heading"), context: context)
                let index = (native.string as NSString).range(of: "Heading").location
                let style = try #require(native.attribute(.paragraphStyle, at: index, effectiveRange: nil) as? NSParagraphStyle)
                #expect(style.paragraphSpacingBefore > style.paragraphSpacing)
                #expect(style.paragraphSpacing > 0)
                #expect(style.lineSpacing < DocumentTypography.bodyLineSpacing)
            }
            #expect(DocumentTypography.mobileScale == 1.08)
            #expect(abs(bodySize - 14) < 0.01)
        }

        @Test(arguments: ["x", "\u{6B63}\u{6587}"]) @MainActor func typingAndDeletingInBlankLineKeepsFollowingContentPosition(typed: String)
            throws
        {
            for following in ["Next", "## Next"] {
                let initial = NativeTextAttributes.native(
                    MarkdownFormatting.render("Before\n\n\n" + following), context: EnvironmentValues().fontResolutionContext)
                let storage = NSTextStorage(attributedString: initial)
                let layout = CodeLayoutManager()
                let container = NSTextContainer(size: CGSize(width: 560, height: 10_000))
                storage.addLayoutManager(layout)
                layout.addTextContainer(container)
                func position() -> CGFloat {
                    layout.ensureLayout(for: container)
                    let range = (storage.string as NSString).range(of: "Next")
                    let glyphs = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                    return layout.boundingRect(forGlyphRange: glyphs, in: container).minY
                }
                let before = position()
                let attributes = storage.attributes(at: 7, effectiveRange: nil)
                storage.insert(NSAttributedString(string: typed, attributes: attributes), at: 7)
                NativeTextAttributes.layoutParagraphs(storage)
                #expect(abs(position() - before) < 0.5)
                storage.deleteCharacters(in: NSRange(location: 7, length: typed.utf16.count))
                NativeTextAttributes.layoutParagraphs(storage)
                #expect(abs(position() - before) < 0.5)
            }
        }

        @Test(arguments: ["Body", "\u{6B63}\u{6587}"]) @MainActor func blankAndBodyUseTheSameNativeLineHeight(bodyText: String) throws {
            let text = NativeTextAttributes.native(
                MarkdownFormatting.render(bodyText + "\n\n\nNext"), context: EnvironmentValues().fontResolutionContext)
            let storage = NSTextStorage(attributedString: text)
            let layout = CodeLayoutManager()
            let container = NSTextContainer(size: CGSize(width: 560, height: 10_000))
            storage.addLayoutManager(layout)
            layout.addTextContainer(container)
            layout.ensureLayout(for: container)
            let bodyGlyph = layout.glyphIndexForCharacter(at: 0)
            let blankGlyph = layout.glyphIndexForCharacter(at: bodyText.utf16.count + 1)
            let body = layout.lineFragmentRect(forGlyphAt: bodyGlyph, effectiveRange: nil)
            let blank = layout.lineFragmentRect(forGlyphAt: blankGlyph, effectiveRange: nil)
            // CJK fallback metrics can differ by a fraction of a Retina pixel.
            #expect(abs(body.height - blank.height) < 0.5)
            #expect(abs(body.maxY - blank.minY) < 0.01)
        }

        @Test @MainActor func whitespaceOnlyParagraphsKeepTheirSemanticLayoutWhenFilled() throws {
            for role in ["body", "heading:1", "heading:2", "heading:3"] {
                var blank = AttributedString(" \t\n")
                blank.font = ParagraphEditing.font(for: role)
                blank[ParagraphStyleAttribute.self] = role
                let native = NativeTextAttributes.native(blank, context: EnvironmentValues().fontResolutionContext)
                let paragraph = try #require(native.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
                var filled = AttributedString("Text\n")
                filled.font = ParagraphEditing.font(for: role)
                filled[ParagraphStyleAttribute.self] = role
                let filledNative = NativeTextAttributes.native(filled, context: EnvironmentValues().fontResolutionContext)
                let filledStyle = try #require(filledNative.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
                #expect(paragraph == filledStyle)
                #expect(paragraph.maximumLineHeight == paragraph.minimumLineHeight)
                #expect(native.string == " \t\n")
                #expect(native.attribute(.weaveParagraphStyle, at: 0, effectiveRange: nil) as? String == role)
            }
        }

        @Test @MainActor func blankParagraphsDoNotStackMarginsOrLoseTheirNaturalHeight() throws {
            let source = "Body\n\n\n## Heading\n\nNext"
            let native = NativeTextAttributes.native(MarkdownFormatting.render(source), context: EnvironmentValues().fontResolutionContext)
            let string = native.string as NSString
            let body = try #require(native.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
            let blank = try #require(native.attribute(.paragraphStyle, at: 5, effectiveRange: nil) as? NSParagraphStyle)
            let heading = try #require(
                native.attribute(.paragraphStyle, at: string.range(of: "Heading").location, effectiveRange: nil) as? NSParagraphStyle)
            #expect(native.string == "Body\n\nHeading\nNext")
            #expect(body.paragraphSpacing == 8)
            #expect(blank.maximumLineHeight == blank.minimumLineHeight)
            #expect(blank.lineSpacing == body.lineSpacing)
            #expect(heading.paragraphSpacingBefore == 12)
            #expect(heading.paragraphSpacing == 8)
            #expect(
                MarkdownFormatting.serialize(NativeTextAttributes.rich(native), context: EnvironmentValues().fontResolutionContext)
                    == source)
        }

        @Test @MainActor func explicitBodyRoleDoesNotAcquireHeadingSpacingAtLargeFontSizes() throws {
            let text = NSMutableAttributedString(
                string: "Large body", attributes: [.font: NSFont.systemFont(ofSize: 32), .weaveParagraphStyle: "body"])
            NativeTextAttributes.layoutParagraphs(text)
            let paragraph = try #require(text.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
            #expect(paragraph.lineSpacing == 6)
            #expect(paragraph.paragraphSpacingBefore == 0)
            #expect(paragraph.paragraphSpacing == 8)
        }

        @Test @MainActor func fontScalingDoesNotAccumulateAcrossEdits() throws {
            let context = EnvironmentValues().fontResolutionContext
            var text = MarkdownFormatting.render("# 标题\n正文 **强调** [链接](https://apple.com)")
            let initial = NativeTextAttributes.native(text, context: context)
            for _ in 0..<5 {
                text = NativeTextAttributes.rich(NativeTextAttributes.native(text, context: context))
            }
            let final = NativeTextAttributes.native(text, context: context)
            #expect(initial.string == final.string)
            for index in 0..<initial.length {
                let before = try #require(initial.attribute(.font, at: index, effectiveRange: nil) as? NSFont)
                let after = try #require(final.attribute(.font, at: index, effectiveRange: nil) as? NSFont)
                #expect(abs(before.pointSize - after.pointSize) < 0.01)
            }
            let linkRange = try #require(text.range(of: "链接"))
            #expect(text[linkRange].link == URL(string: "https://apple.com"))
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
            let restoredFont = try #require(
                restoredNative.attribute(.font, at: (restoredNative.string as NSString).range(of: "hello").location, effectiveRange: nil)
                    as? NSFont)
            let originalFont = try #require(
                native.attribute(.font, at: (native.string as NSString).range(of: "hello").location, effectiveRange: nil) as? NSFont)
            #expect(abs(restoredFont.pointSize - originalFont.pointSize) < 0.01)
            let helloRange = try #require(restored.richText.range(of: "hello"))
            let helloFont = try #require(restored.richText[helloRange].font)
            #expect(helloFont.resolve(in: context).isMonospaced)
            #expect(restored.richText[helloRange][CodeStyleAttribute.self] == "inline")
            let codeRange = try #require(restored.richText.range(of: "let a = 1"))
            let printRange = try #require(restored.richText.range(of: "print(a)"))
            let bodyRange = try #require(restored.richText.range(of: "正文"))
            let code = try #require(restored.richText[codeRange][CodeStyleAttribute.self])
            #expect(code.hasPrefix("block:"))
            #expect(restored.richText[printRange][CodeStyleAttribute.self] == code)
            #expect(restored.richText[bodyRange][CodeStyleAttribute.self] == nil)
            let range = (native.string as NSString).range(of: "let a = 1")
            #expect(native.attribute(.backgroundColor, at: range.location, effectiveRange: nil) == nil)
            let paragraph = try #require(native.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle)
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

        @Test @MainActor func paragraphsHaveReadingRhythmAndHangingIndents() throws {
            let native = NativeTextAttributes.native(
                MarkdownFormatting.render("# 标题\n正文\n- 列表\n> 引用"), context: EnvironmentValues().fontResolutionContext)
            let string = native.string as NSString
            let title = try #require(native.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
            let body = try #require(
                native.attribute(.paragraphStyle, at: string.range(of: "正文").location, effectiveRange: nil) as? NSParagraphStyle)
            let list = try #require(
                native.attribute(.paragraphStyle, at: string.range(of: "•").location, effectiveRange: nil) as? NSParagraphStyle)
            #expect(title.paragraphSpacing >= body.paragraphSpacing)
            #expect(body.lineSpacing == 6)
            #expect(list.headIndent > list.firstLineHeadIndent)
        }
    }
#endif
