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
    let codeStyle: CodeStyleAttribute
    let paragraphStyle: ParagraphStyleAttribute
}

extension NSAttributedString.Key {
    static let weaveParagraphStyle = NSAttributedString.Key(ParagraphStyleAttribute.name)
    static let weaveCodeStyle = NSAttributedString.Key(CodeStyleAttribute.name)
}

/// Draw code surfaces behind text while retaining native selection, caret and scrolling.
final class CodeLayoutManager: NSLayoutManager {
    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        guard let storage = textStorage else {
            super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
            return
        }
        storage.enumerateAttribute(.weaveCodeStyle, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard let style = value as? String else { return }
            let glyphs = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard NSIntersectionRange(glyphs, glyphsToShow).length > 0,
                  let container = self.textContainer(forGlyphAt: glyphs.location, effectiveRange: nil) else { return }
            #if os(macOS)
            NSColor.labelColor.withAlphaComponent(0.06).setFill()
            #else
            UIColor.label.withAlphaComponent(0.06).setFill()
            #endif
            if style.hasPrefix("block:") {
                var rect = self.boundingRect(forGlyphRange: glyphs, in: container)
                rect.origin.x = container.lineFragmentPadding
                rect.size.width = max(0, container.size.width - 2 * container.lineFragmentPadding)
                rect = rect.insetBy(dx: 0, dy: -8).offsetBy(dx: origin.x, dy: origin.y)
                self.fill(rect, radius: 8)
            } else {
                self.enumerateEnclosingRects(forGlyphRange: glyphs, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: container) { rect, _ in
                    self.fill(rect.insetBy(dx: -3, dy: -1).offsetBy(dx: origin.x, dy: origin.y), radius: 3)
                }
            }
        }
        storage.enumerateAttribute(.weaveParagraphStyle, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard value as? String == "quote" else { return }
            let glyphs = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard NSIntersectionRange(glyphs, glyphsToShow).length > 0,
                  let container = self.textContainer(forGlyphAt: glyphs.location, effectiveRange: nil) else { return }
            var rect = self.boundingRect(forGlyphRange: glyphs, in: container)
            rect.origin.x = container.lineFragmentPadding + 4
            rect.size.width = 2
            #if os(macOS)
            NSColor.labelColor.withAlphaComponent(0.22).setFill()
            #else
            UIColor.label.withAlphaComponent(0.22).setFill()
            #endif
            self.fill(rect.offsetBy(dx: origin.x, dy: origin.y), radius: 1)
        }
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
    }

    private func fill(_ rect: CGRect, radius: CGFloat) {
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
    #if os(macOS)
    static let readingScale: CGFloat = 1.3
    #else
    static let readingScale: CGFloat = 1.08
    #endif

    static func displayFont(_ font: CTFont) -> CTFont {
        CTFontCreateCopyWithAttributes(font, CTFontGetSize(font) * readingScale, nil, nil)
    }

    static func storedFont(_ font: CTFont) -> CTFont {
        CTFontCreateCopyWithAttributes(font, CTFontGetSize(font) / readingScale, nil, nil)
    }

    static func layoutParagraphs(_ text: NSMutableAttributedString) {
        let source = text.string as NSString
        var location = 0
        while location < source.length {
            let range = source.paragraphRange(for: NSRange(location: location, length: 0))
            let content = source.substring(with: range).trimmingCharacters(in: .newlines)
            let font = text.attribute(.font, at: location, effectiveRange: nil) as? PlatformFont
            let size = font?.pointSize ?? 17
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 6
            paragraph.paragraphSpacing = 8
            if text.attribute(.weaveParagraphStyle, at: location, effectiveRange: nil) == nil {
                if size >= 26 { text.addAttribute(.weaveParagraphStyle, value: "heading:1", range: range) }
                else if size >= 21 { text.addAttribute(.weaveParagraphStyle, value: "heading:2", range: range) }
            }
            if content.isEmpty {
                paragraph.lineSpacing = 0
                // Empty paragraphs remain editable lines; use the font's natural
                // height so the insertion point isn't compressed into a spacer.
                paragraph.paragraphSpacing = 0
            } else if size >= 26 {
                paragraph.lineSpacing = 3
                paragraph.paragraphSpacingBefore = location == 0 ? 0 : 24
                paragraph.paragraphSpacing = 14
            } else if size >= 21 {
                paragraph.lineSpacing = 4
                paragraph.paragraphSpacingBefore = 20
                paragraph.paragraphSpacing = 10
            }
            if content.trimmingCharacters(in: .whitespaces).hasPrefix("• ") || content.hasPrefix("☐ ") || content.hasPrefix("☑ ") || content.range(of: #"^\d+\. "#, options: .regularExpression) != nil {
                paragraph.headIndent = 24
                paragraph.paragraphSpacing = 4
            }
            if content.hasPrefix("│ ") || text.attribute(.weaveParagraphStyle, at: location, effectiveRange: nil) as? String == "quote" {
                text.addAttribute(.weaveParagraphStyle, value: "quote", range: range)
                paragraph.firstLineHeadIndent = content.hasPrefix("│ ") ? 12 : 20
                paragraph.headIndent = 28
                if content.hasPrefix("│ ") {
                    #if os(macOS)
                    text.addAttribute(.foregroundColor, value: NSColor.clear, range: NSRange(location: location, length: 1))
                    #else
                    text.addAttribute(.foregroundColor, value: UIColor.clear, range: NSRange(location: location, length: 1))
                    #endif
                }
                paragraph.paragraphSpacing = 4
            }
            if let code = text.attribute(.weaveCodeStyle, at: location, effectiveRange: nil) as? String, code.hasPrefix("block:") {
                let previous = location > 0 ? text.attribute(.weaveCodeStyle, at: location - 1, effectiveRange: nil) as? String : nil
                let next = NSMaxRange(range) < text.length ? text.attribute(.weaveCodeStyle, at: NSMaxRange(range), effectiveRange: nil) as? String : nil
                paragraph.maximumLineHeight = 0
                paragraph.lineSpacing = 3
                paragraph.firstLineHeadIndent = 14
                paragraph.headIndent = 14
                paragraph.tailIndent = -14
                paragraph.paragraphSpacingBefore = previous == code ? 0 : 12
                paragraph.paragraphSpacing = next == code ? 0 : 14
            }
            let level = MarkdownShortcut.listPrefix(content) == nil ? 0 : content.prefix(while: { $0 == "\t" }).count
            paragraph.headIndent += CGFloat(level) * 24
            paragraph.tabStops = (1...12).map { NSTextTab(textAlignment: .left, location: CGFloat($0) * 24) }
            if text.attribute(.weaveParagraphStyle, at: location, effectiveRange: nil) as? String == "heading:3" {
                paragraph.paragraphSpacingBefore = 18
                paragraph.paragraphSpacing = 8
            }
            text.addAttribute(.paragraphStyle, value: paragraph, range: range)
            location = NSMaxRange(range)
        }
    }

    static func native(_ text: AttributedString, context: Font.Context) -> NSAttributedString {
        let result = NSMutableAttributedString(string: String(text.characters))
        for run in text.runs {
            let range = NSRange(run.range, in: text)
            var attributes: [NSAttributedString.Key: Any] = [:]
            attributes[.font] = displayFont((run.font ?? .body).resolve(in: context).ctFont)
            if let style = run[ParagraphStyleAttribute.self] { attributes[.weaveParagraphStyle] = style }
            if let style = run[CodeStyleAttribute.self] {
                attributes[.weaveCodeStyle] = style
            } else if (run.font ?? .body).resolve(in: context).isMonospaced {
                // Compatibility with documents saved before code roles were persisted.
                attributes[.weaveCodeStyle] = run.backgroundColor == Color.secondary.opacity(0.1) ? "legacy-block" : "inline"
            }
            if let link = run.link { attributes[.link] = link }
            if run.underlineStyle != nil { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            if run.strikethroughStyle != nil { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            #if os(macOS)
            attributes[.foregroundColor] = run.foregroundColor.map(NSColor.init) ?? NSColor.textColor
            if let color = run.backgroundColor { attributes[.backgroundColor] = NSColor(color) }
            #else
            attributes[.foregroundColor] = run.foregroundColor.map(UIColor.init) ?? UIColor.label
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
        return result
    }

    static func rich(_ text: NSAttributedString) -> AttributedString {
        var result = AttributedString(text.string)
        text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attributes, nsRange, _ in
            guard let range = Range<AttributedString.Index>(nsRange, in: result) else { return }
            if let style = attributes[.weaveParagraphStyle] as? String { result[range][ParagraphStyleAttribute.self] = style }
            if let style = attributes[.weaveCodeStyle] as? String { result[range][CodeStyleAttribute.self] = style }
            if let font = attributes[.font] as? PlatformFont { result[range].font = Font(storedFont(font as CTFont)) }
            if let link = attributes[.link] as? URL { result[range].link = link }
            else if let link = attributes[.link] as? String { result[range].link = URL(string: link) }
            if let style = attributes[.underlineStyle] as? Int, style != 0 { result[range].underlineStyle = .single }
            if let style = attributes[.strikethroughStyle] as? Int, style != 0 { result[range].strikethroughStyle = .single }
            #if os(macOS)
            if let color = attributes[.foregroundColor] as? NSColor, color != .textColor, color != .clear { result[range].foregroundColor = Color(nsColor: color) }
            if let color = attributes[.backgroundColor] as? NSColor { result[range].backgroundColor = Color(nsColor: color) }
            #else
            if let color = attributes[.foregroundColor] as? UIColor, color != .label, color != .clear { result[range].foregroundColor = Color(uiColor: color) }
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
    var onEditLink: () -> Void = {}
    @Environment(\.fontResolutionContext) private var fontContext

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor
    final class Coordinator: NSObject {
        var parent: NativeRichTextEditor
        private var lastValue: AttributedString
        fileprivate var isUpdating = false
        weak var textView: PlatformTextView?

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

        fileprivate func update(_ parent: NativeRichTextEditor) {
            self.parent = parent
            guard let textView, !hasMarkedText else { return }
            isUpdating = true
            defer { isUpdating = false }
            if parent.text != lastValue {
                storage?.setAttributedString(NativeTextAttributes.native(parent.text, context: parent.fontContext))
                lastValue = parent.text
            }
            let range: NSRange
            switch parent.selection.indices(in: parent.text) {
            case .insertionPoint(let index): range = NSRange(index..<index, in: parent.text)
            case .ranges(let ranges):
                guard let first = ranges.ranges.first else { return }
                range = NSRange(first, in: parent.text)
            }
            if NSMaxRange(range) <= (storage?.length ?? 0), range != currentSelection { setSelection(range) }
            let attributes = parent.selection.typingAttributes(in: parent.text)
            let sample = NativeTextAttributes.native(AttributedString(" ", attributes: attributes), context: parent.fontContext)
            textView.typingAttributes = sample.attributes(at: 0, effectiveRange: nil)
        }

        fileprivate func publish() {
            guard !isUpdating, let storage else { return }
            if !hasMarkedText {
                isUpdating = true
                NativeTextAttributes.layoutParagraphs(storage)
                isUpdating = false
            }
            let value = NativeTextAttributes.rich(storage)
            lastValue = value
            parent.text = value
            publishSelection(in: value)
        }

        fileprivate func publishSelection(in value: AttributedString? = nil) {
            guard !isUpdating, !hasMarkedText, let textView else { return }
            let text = value ?? parent.text
            guard let range = Range<AttributedString.Index>(currentSelection, in: text) else { return }
            if range.isEmpty {
                let sample = NativeTextAttributes.rich(NSAttributedString(string: " ", attributes: textView.typingAttributes))
                parent.selection = AttributedTextSelection(insertionPoint: range.lowerBound, typingAttributes: sample.runs.first?.attributes)
            } else { parent.selection = AttributedTextSelection(range: range) }
        }

        func intercept(range: NSRange, replacement: String?) -> Bool {
            guard !isUpdating, !hasMarkedText, let textView, let storage, let replacement,
                  textView.undoManager?.isUndoing != true, textView.undoManager?.isRedoing != true else { return true }
            if range.length > 0, let url = URL(string: replacement),
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
            let paragraph = source.paragraphRange(for: NSRange(location: min(caret.location, source.length), length: 0))
            let line = source.substring(with: paragraph).trimmingCharacters(in: .newlines)
            let role = textView.typingAttributes[.weaveParagraphStyle] as? String
            let code = textView.typingAttributes[.weaveCodeStyle] as? String
            var contextual: MarkdownShortcut.Edit?
            if replacement == "\n", range.length == 0 {
                if role?.hasPrefix("heading:") == true {
                    contextual = .init(range: range, replacement: "\n", style: .body)
                } else if code?.hasPrefix("block:") == true, line.isEmpty {
                    contextual = .init(range: range, replacement: "", style: .body)
                } else if role == "quote", line.isEmpty {
                    contextual = .init(range: range, replacement: "", style: .body)
                } else if code == "inline" {
                    contextual = .init(range: range, replacement: "\n", style: .body)
                }
            }
            if replacement.isEmpty, range.length == 1, caret.length == 0 {
                if let item = MarkdownShortcut.listPrefix(line), caret.location == paragraph.location + item.prefix.utf16.count {
                    contextual = .init(range: NSRange(location: paragraph.location, length: item.prefix.utf16.count), replacement: "", style: .body)
                } else if caret.location == paragraph.location, role?.hasPrefix("heading:") == true || role == "quote" || code?.hasPrefix("block:") == true {
                    contextual = .init(range: NSRange(location: caret.location, length: 0), replacement: "", style: .body)
                }
            }
            if replacement == "\t" || replacement == "\u{19}", caret.length == 0, MarkdownShortcut.listPrefix(line) != nil {
                if replacement == "\t", line.prefix(while: { $0 == "\t" }).count < 8 {
                    contextual = .init(range: NSRange(location: paragraph.location, length: 0), replacement: "\t", style: .bullet)
                } else if replacement == "\u{19}", line.hasPrefix("\t") {
                    contextual = .init(range: NSRange(location: paragraph.location, length: 1), replacement: "", style: .bullet)
                } else { return false }
            }
            let shortcut = code == nil ? MarkdownShortcut.match(text: storage.string, range: range, replacement: replacement, hasMarkedText: false) : nil
            guard let edit = contextual ?? shortcut else { return true }
            var attributes = textView.typingAttributes
            let originalAttributes = attributes
            let base = (attributes[.font] as? PlatformFont)
            let font: Font
            switch edit.style {
            case .heading(let level): font = level == 1 ? .title : level == 2 ? .title2 : .headline
            case .bold: font = base.map { Font(NativeTextAttributes.storedFont($0 as CTFont)).bold() } ?? .body.bold()
            case .italic: font = base.map { Font(NativeTextAttributes.storedFont($0 as CTFont)).italic() } ?? .body.italic()
            case .code: font = .body.monospaced()
            case .codeBlock: font = .body.monospaced()
            case .body, .bullet, .quote, .numbered, .task: font = .body
            }
            attributes[.font] = NativeTextAttributes.displayFont(font.resolve(in: parent.fontContext).ctFont)
            switch edit.style {
            case .heading(let level):
                attributes[.weaveParagraphStyle] = "heading:\(level)"
                attributes.removeValue(forKey: .weaveCodeStyle)
            case .codeBlock:
                attributes[.weaveCodeStyle] = "block:" + UUID().uuidString
                attributes[.weaveParagraphStyle] = "code"
            case .body, .bullet, .numbered, .task, .quote:
                attributes[.weaveParagraphStyle] = edit.style == .quote ? "quote" : "body"
                attributes.removeValue(forKey: .weaveCodeStyle)
                attributes.removeValue(forKey: .link)
            default: break
            }
            let inserted: NSAttributedString
            switch edit.style {
            case .bold, .italic, .code:
                let markerLength = edit.style == .bold ? 2 : 1
                let contentRange = NSRange(location: edit.range.location + markerLength, length: edit.replacement.utf16.count)
                let content = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: contentRange))
                content.enumerateAttribute(.font, in: NSRange(location: 0, length: content.length)) { value, runRange, _ in
                    let existing = (value as? PlatformFont).map { Font(NativeTextAttributes.storedFont($0 as CTFont)) } ?? .body
                    let styled: Font = edit.style == .bold ? existing.bold() : edit.style == .italic ? existing.italic() : existing.monospaced()
                    content.addAttribute(.font, value: NativeTextAttributes.displayFont(styled.resolve(in: parent.fontContext).ctFont), range: runRange)
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
            // inherit code/quote attributes again from the preceding newline.
            if edit.style == .body, contextual != nil, replacement == "\n", inserted.length == 0,
               edit.range.location > 0, source.substring(with: NSRange(location: edit.range.location - 1, length: 1)) == "\n" {
                updated.setAttributes(attributes, range: NSRange(location: edit.range.location - 1, length: 1))
            }
            let after: NSRange
            if replacement == "\t" || replacement == "\u{19}" {
                after = NSRange(location: caret.location + inserted.length - edit.range.length, length: 0)
            } else { after = NSRange(location: edit.range.location + inserted.length, length: 0) }
            if edit.style == .body, contextual != nil, replacement != "\n", updated.length > after.location {
                let affected = (updated.string as NSString).paragraphRange(for: NSRange(location: after.location, length: 0))
                updated.removeAttribute(.weaveCodeStyle, range: affected)
                updated.addAttribute(.weaveParagraphStyle, value: "body", range: affected)
                updated.addAttribute(.font, value: attributes[.font]!, range: affected)
            }
            let nextAttributes: [NSAttributedString.Key: Any]
            switch edit.style {
            case .bold, .italic, .code: nextAttributes = originalAttributes
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

        fileprivate func toggleTask(at index: Int) -> Bool {
            guard !hasMarkedText, let storage, let view = textView, index < storage.length else { return false }
            let source = storage.string as NSString
            let paragraph = source.paragraphRange(for: NSRange(location: index, length: 0))
            let line = source.substring(with: paragraph)
            let indent = line.prefix(while: { $0 == "\t" }).count
            let markerIndex = paragraph.location + indent
            guard index == markerIndex else { return false }
            let marker = source.substring(with: NSRange(location: markerIndex, length: 1))
            guard marker == "☐" || marker == "☑" else { return false }
            registerUndo(text: NSAttributedString(attributedString: storage), selection: currentSelection, attributes: view.typingAttributes)
            let updated = NSMutableAttributedString(attributedString: storage)
            updated.replaceCharacters(in: NSRange(location: markerIndex, length: 1), with: marker == "☐" ? "☑" : "☐")
            apply(text: updated, selection: currentSelection, attributes: view.typingAttributes)
            view.undoManager?.setActionName("切换待办")
            return true
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

        private func apply(text: NSAttributedString, selection: NSRange, attributes: [NSAttributedString.Key: Any]) {
            isUpdating = true
            storage?.setAttributedString(text)
            setSelection(selection)
            textView?.typingAttributes = attributes
            #if os(macOS)
            textView?.didChangeText()
            #endif
            isUpdating = false
            publish()
        }
    }
}

#if os(macOS)
private final class ReadingMacTextView: NSTextView {
    var toggleTask: ((Int) -> Bool)?
    var editLink: (() -> Void)?
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
        if let layoutManager, let textContainer {
            let local = CGPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
            let glyph = layoutManager.glyphIndex(for: local, in: textContainer)
            if glyph < layoutManager.numberOfGlyphs,
               layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: textContainer).insetBy(dx: -3, dy: -3).contains(local),
               toggleTask?(layoutManager.characterIndexForGlyph(at: glyph)) == true { return }
        }
        super.mouseDown(with: event)
    }
}

private final class ReadingScrollView: NSScrollView {
    override func tile() {
        super.tile()
        guard let view = documentView as? NSTextView else { return }
        let inset = max(32, (contentSize.width - 728) / 2)
        if view.textContainerInset.width != inset {
            view.textContainerInset = NSSize(width: inset, height: 36)
        }
    }
}

extension NativeRichTextEditor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = ReadingScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        let view = ReadingMacTextView(frame: scroll.contentView.bounds)
        view.editLink = { [weak coordinator = context.coordinator] in coordinator?.parent.onEditLink() }
        view.toggleTask = { [weak coordinator = context.coordinator] index in coordinator?.toggleTask(at: index) ?? false }
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
        view.textContainerInset = NSSize(width: 32, height: 36)
        view.setAccessibilityLabel("记录正文")
        view.setAccessibilityIdentifier("note-editor")
        view.textStorage?.setAttributedString(NativeTextAttributes.native(text, context: fontContext))
        view.delegate = context.coordinator
        context.coordinator.textView = view
        context.coordinator.update(self)
        if text.characters.isEmpty {
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
        if selector == #selector(NSResponder.insertBacktab(_:)) {
            return !intercept(range: textView.selectedRange(), replacement: "\u{19}")
        }
        if selector == #selector(NSResponder.insertLineBreak(_:)) {
            textView.insertText("\u{2028}", replacementRange: textView.selectedRange())
            return true
        }
        return false
    }
    func textDidChange(_ notification: Notification) { publish() }
    func textViewDidChangeSelection(_ notification: Notification) { publishSelection() }
}
#else
private final class ReadingTextView: UITextView {
    var toggleTask: ((Int) -> Bool)?
    @objc func tappedTask(_ recognizer: UITapGestureRecognizer) {
        let point = recognizer.location(in: self)
        let local = CGPoint(x: point.x - textContainerInset.left, y: point.y - textContainerInset.top)
        let glyph = layoutManager.glyphIndex(for: local, in: textContainer)
        guard glyph < layoutManager.numberOfGlyphs,
              layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: textContainer).insetBy(dx: -4, dy: -4).contains(local) else { return }
        _ = toggleTask?(layoutManager.characterIndexForGlyph(at: glyph))
    }

    override func layoutSubviews() {
        let inset = max(24, (bounds.width - 728) / 2)
        if textContainerInset.left != inset {
            textContainerInset = UIEdgeInsets(top: 28, left: inset, bottom: 40, right: inset)
        }
        super.layoutSubviews()
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
        view.toggleTask = { [weak coordinator = context.coordinator] index in coordinator?.toggleTask(at: index) ?? false }
        let tap = UITapGestureRecognizer(target: view, action: #selector(ReadingTextView.tappedTask(_:)))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
        view.font = .preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.textContainerInset = UIEdgeInsets(top: 28, left: 8, bottom: 40, right: 8)
        view.allowsEditingTextAttributes = true
        view.smartQuotesType = .no
        view.smartDashesType = .no
        view.accessibilityLabel = "记录正文"
        view.accessibilityIdentifier = "note-editor"
        view.attributedText = NativeTextAttributes.native(text, context: fontContext)
        view.delegate = context.coordinator
        context.coordinator.textView = view
        context.coordinator.update(self)
        if text.characters.isEmpty {
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
    func textViewDidChange(_ textView: UITextView) { publish() }
    func textViewDidChangeSelection(_ textView: UITextView) { publishSelection() }
}
#endif
