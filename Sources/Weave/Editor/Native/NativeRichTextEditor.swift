import SwiftUI

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

@MainActor
struct NativeRichTextEditor {
    @Binding var text: AttributedString
    @Binding var selection: AttributedTextSelection
    var focusWhenEmpty = true
    var focusRequest = 0
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
        private var pendingNativeEditRange: NSRange?
        private var handledFocusRequest: Int
        weak var textView: PlatformTextView?
        private let inputFeatures = EditorFeatureRegistry()
        private let tables = TableOverlayController()
        private let codeHeaders = CodeHeaderOverlayController()

        init(parent: NativeRichTextEditor) {
            self.parent = parent
            lastValue = parent.text
            handledFocusRequest = 0
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
            defer {
                isUpdating = false
                refreshTables()
            }
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
            if NSMaxRange(range) <= (storage?.length ?? 0), range != currentSelection { setSelection(range) }
            let attributes = parent.selection.typingAttributes(in: parent.text)
            let source = (storage?.string ?? "") as NSString
            let paragraphRange = source.paragraphRange(for: NSRange(location: min(range.location, source.length), length: 0))
            let isBlank = source.substring(with: paragraphRange).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let sample = NativeTextAttributes.native(
                AttributedString(isBlank ? "\n" : " ", attributes: attributes), context: parent.fontContext)
            var nativeAttributes = sample.attributes(at: 0, effectiveRange: nil)
            // A synthetic space has body margins. Reuse the actual paragraph's
            // layout when restoring typing state so clicking cannot change its height.
            if let storage, paragraphRange.location < storage.length,
                storage.attribute(.weaveParagraphStyle, at: paragraphRange.location, effectiveRange: nil) as? String == nativeAttributes[
                    .weaveParagraphStyle] as? String,
                storage.attribute(.weaveCodeStyle, at: paragraphRange.location, effectiveRange: nil) as? String == nativeAttributes[
                    .weaveCodeStyle] as? String
            {
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
            if parent.focusRequest != handledFocusRequest {
                handledFocusRequest = parent.focusRequest
                DispatchQueue.main.async { [weak textView] in
                    #if os(macOS)
                        textView?.window?.makeFirstResponder(textView)
                    #else
                        textView?.becomeFirstResponder()
                    #endif
                }
            }
        }

        fileprivate func publish(around affected: NSRange? = nil) {
            guard !isUpdating, let storage else { return }
            if !hasMarkedText {
                isUpdating = true
                NativeTextAttributes.layoutParagraphs(storage, around: affected)
                NativeTextAttributes.highlightCode(storage, around: affected)
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
            let text = value ?? parent.text
            guard let range = Range<AttributedString.Index>(currentSelection, in: text) else { return }
            if range.isEmpty {
                let sample = NativeTextAttributes.rich(NSAttributedString(string: " ", attributes: textView.typingAttributes))
                parent.selection = AttributedTextSelection(
                    insertionPoint: range.lowerBound, typingAttributes: sample.runs.first?.attributes)
            } else {
                parent.selection = AttributedTextSelection(range: range)
            }
        }

        fileprivate func refreshTables() {
            guard let textView else { return }
            codeHeaders.refresh(
                in: textView,
                onLanguage: { [weak self] id, language in
                    self?.changeCodeLanguage(id: id, language: language)
                })
            tables.refresh(
                in: textView,
                onChange: { [weak self] id, table in
                    self?.changeTable(id: id, table: table)
                },
                onExit: { [weak self] index in
                    // Let SwiftUI resign the cell before restoring the document responder.
                    DispatchQueue.main.async { [weak self] in self?.exitTable(at: index) }
                })
        }

        func changeCodeLanguage(id: String, language: String) {
            guard !hasMarkedText, let storage, let view = textView else { return }
            var target: NSRange?
            storage.enumerateAttribute(.weaveCodeStyle, in: NSRange(location: 0, length: storage.length)) { value, range, stop in
                if value as? String == id {
                    target = range
                    stop.pointee = true
                }
            }
            guard let target,
                storage.attribute(.weaveCodeLanguage, at: target.location, effectiveRange: nil) as? String != language
            else { return }
            registerUndo(
                text: NSAttributedString(attributedString: storage), selection: currentSelection, attributes: view.typingAttributes)
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
                registerUndo(
                    text: NSAttributedString(attributedString: storage), selection: currentSelection, attributes: view.typingAttributes)
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
            guard let encoded = try? RichTextClipboard.encode(selected) else {
                #if os(macOS)
                    NSSound.beep()
                #endif
                return true  // Never fall back to a lossy cut of a structured block.
            }
            let plain = hasTable ? MarkdownFormatting.serialize(selected, context: parent.fontContext) : String(selected.characters)
            let nativeSelection = storage.attributedSubstring(from: range)
            let richTextData = try? nativeSelection.data(
                from: NSRange(location: 0, length: nativeSelection.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
            )
            #if os(macOS)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setData(encoded, forType: NSPasteboard.PasteboardType("app.weave.richtext"))
                if let richTextData { NSPasteboard.general.setData(richTextData, forType: .rtf) }
                NSPasteboard.general.setString(plain, forType: .string)
            #else
                var item: [String: Any] = ["app.weave.richtext": encoded, "public.utf8-plain-text": plain]
                if let richTextData { item["public.rtf"] = richTextData }
                UIPasteboard.general.setItems([item])
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
                view.typingAttributes[.weaveCodeStyle] == nil
            else { return false }
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
                storage.attribute(.weaveTable, at: target.location, effectiveRange: nil) as? Data != encoded
            else { return }
            registerUndo(
                text: NSAttributedString(attributedString: storage), selection: currentSelection, attributes: view.typingAttributes)
            isUpdating = true
            storage.addAttributes([.weaveTable: encoded, .attachment: TableTextAttachment(table: table)], range: target)
            isUpdating = false
            publish()
            view.undoManager?.setActionName("编辑表格")
        }

        func intercept(range: NSRange, replacement: String?) -> Bool {
            guard !isUpdating, !hasMarkedText, let textView, let storage, let replacement,
                textView.undoManager?.isUndoing != true, textView.undoManager?.isRedoing != true
            else { return true }
            textView.typingAttributes.removeValue(forKey: .attachment)
            textView.typingAttributes.removeValue(forKey: .weaveTable)
            let context = EditorInputContext(
                storage: storage,
                typingAttributes: textView.typingAttributes,
                range: range,
                replacement: replacement,
                selection: currentSelection)
            guard let command = inputFeatures.command(for: context) else {
                if replacement.isEmpty, range.length > 0 {
                    prepareTypingAttributesAfterInlineDeletion(range)
                }
                let changed = NSRange(location: range.location, length: max(range.length, replacement.utf16.count))
                pendingNativeEditRange = pendingNativeEditRange.map { NSUnionRange($0, changed) } ?? changed
                return true
            }
            return execute(command, context: context, storage: storage, textView: textView)
        }

        private func execute(
            _ command: EditorInputCommand,
            context: EditorInputContext,
            storage: NSTextStorage,
            textView: PlatformTextView
        ) -> Bool {
            switch command {
            case .applyLink(let url):
                registerUndo(
                    text: NSAttributedString(attributedString: storage),
                    selection: context.selection,
                    attributes: textView.typingAttributes)
                let updated = NSMutableAttributedString(attributedString: storage)
                updated.addAttribute(.link, value: url, range: context.range)
                apply(text: updated, selection: context.range, attributes: textView.typingAttributes)
            case .preserveEmptyQuote:
                preserveEmptyQuote(context: context, storage: storage, textView: textView)
            case .indentCode(let outdent):
                applyCodeIndent(outdent: outdent, context: context, storage: storage, textView: textView)
            case .continueCodeLine(let prefix):
                continueCodeLine(prefix: prefix, context: context, storage: storage, textView: textView)
            case .edit(let edit, let origin):
                apply(edit: edit, origin: origin, context: context, storage: storage, textView: textView)
            case .consume:
                break
            }
            return false
        }

        private func preserveEmptyQuote(
            context: EditorInputContext,
            storage: NSTextStorage,
            textView: PlatformTextView
        ) {
            registerUndo(
                text: NSAttributedString(attributedString: storage),
                selection: context.selection,
                attributes: textView.typingAttributes)
            let next = NSMutableAttributedString(attributedString: storage)
            next.deleteCharacters(in: context.range)
            var attributes = textView.typingAttributes
            attributes[.weaveQuote] = true
            #if os(macOS)
                attributes[.foregroundColor] = NSColor.secondaryLabelColor
            #else
                attributes[.foregroundColor] = UIColor.secondaryLabel
            #endif
            attributes[.weaveQuoteColor] = true
            apply(text: next, selection: NSRange(location: context.range.location, length: 0), attributes: attributes)
        }

        private func applyCodeIndent(
            outdent: Bool,
            context: EditorInputContext,
            storage: NSTextStorage,
            textView: PlatformTextView
        ) {
            var value = NativeTextAttributes.rich(storage)
            guard let selected = Range<AttributedString.Index>(context.selection, in: value) else { return }
            var selection =
                selected.isEmpty
                ? AttributedTextSelection(insertionPoint: selected.lowerBound)
                : AttributedTextSelection(range: selected)
            if CodeBlockEditing.indent(in: &value, selection: &selection, outdent: outdent) {
                registerUndo(
                    text: NSAttributedString(attributedString: storage),
                    selection: context.selection,
                    attributes: textView.typingAttributes)
                let after: NSRange
                switch selection.indices(in: value) {
                case .insertionPoint(let point): after = NSRange(point..<point, in: value)
                case .ranges(let ranges): after = ranges.ranges.first.map { NSRange($0, in: value) } ?? context.selection
                }
                apply(
                    text: NativeTextAttributes.native(value, context: parent.fontContext),
                    selection: after,
                    attributes: textView.typingAttributes)
                textView.undoManager?.setActionName("代码缩进")
                return
            }
            // A newly created empty code block exists only in typing attributes.
            guard !outdent, context.selection.length == 0 else { return }
            registerUndo(
                text: NSAttributedString(attributedString: storage),
                selection: context.selection,
                attributes: textView.typingAttributes)
            let next = NSMutableAttributedString(attributedString: storage)
            next.replaceCharacters(
                in: context.range,
                with: NSAttributedString(string: "    ", attributes: textView.typingAttributes))
            apply(
                text: next,
                selection: NSRange(location: context.range.location + 4, length: 0),
                attributes: textView.typingAttributes)
        }

        private func continueCodeLine(
            prefix: String,
            context: EditorInputContext,
            storage: NSTextStorage,
            textView: PlatformTextView
        ) {
            let newline = "\n" + prefix
            registerUndo(
                text: NSAttributedString(attributedString: storage),
                selection: context.selection,
                attributes: textView.typingAttributes)
            let next = NSMutableAttributedString(attributedString: storage)
            next.replaceCharacters(
                in: context.range,
                with: NSAttributedString(string: newline, attributes: textView.typingAttributes))
            apply(
                text: next,
                selection: NSRange(location: context.range.location + newline.utf16.count, length: 0),
                attributes: textView.typingAttributes)
        }

        private func apply(
            edit: MarkdownShortcut.Edit,
            origin: EditorInputOrigin,
            context: EditorInputContext,
            storage: NSTextStorage,
            textView: PlatformTextView
        ) {
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
                attributes[.weaveCodeLanguage] = CodeBlockEditing.languageTag(from: context.line)
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
                if edit.style == .task { attributes[.weaveTaskChecked] = false } else { attributes.removeValue(forKey: .weaveTaskChecked) }
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
                    let styled: Font =
                        edit.style == .bold
                        ? existing.weight(.bold)
                        : edit.style == .italic
                            ? existing.italic()
                            : edit.style == .code
                                ? DocumentTypography.font(
                                    for: context.role ?? "body",
                                    inlineCode: true,
                                    context: parent.fontContext)
                                : existing
                    content.addAttribute(
                        .font, value: NativeTextAttributes.displayFont(styled.resolve(in: parent.fontContext).ctFont), range: runRange)
                }
                if edit.style == .bold || edit.style == .italic {
                    let flag = edit.style == .bold ? 1 : 2
                    content.enumerateAttribute(.weaveInlineEmphasis, in: NSRange(location: 0, length: content.length)) {
                        value, runRange, _ in
                        content.addAttribute(.weaveInlineEmphasis, value: (value as? Int ?? 0) | flag, range: runRange)
                    }
                }
                if edit.style == .strike {
                    content.addAttribute(
                        .strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: 0, length: content.length))
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
            if edit.style == .body, context.replacement == "\n", inserted.length == 0 {
                let boundary: Int?
                if edit.range.location < updated.length,
                    (updated.string as NSString).substring(with: NSRange(location: edit.range.location, length: 1)) == "\n"
                {
                    boundary = edit.range.location
                } else if edit.range.location > 0,
                    (updated.string as NSString).substring(with: NSRange(location: edit.range.location - 1, length: 1)) == "\n"
                {
                    boundary = edit.range.location - 1
                } else {
                    boundary = nil
                }
                if let boundary {
                    updated.setAttributes(attributes, range: NSRange(location: boundary, length: 1))
                }
            }
            let after: NSRange
            if context.replacement == "\t" || context.replacement == "\u{19}" {
                after = NSRange(location: context.selection.location + inserted.length - edit.range.length, length: 0)
            } else {
                after = NSRange(location: edit.range.location + inserted.length, length: 0)
            }
            if edit.style == .body, origin == .feature, context.replacement != "\n", updated.length > after.location {
                let affected = (updated.string as NSString).paragraphRange(for: NSRange(location: after.location, length: 0))
                updated.removeAttribute(.weaveCodeStyle, range: affected)
                updated.removeAttribute(.weaveCodeLanguage, range: affected)
                updated.removeAttribute(.weaveTaskChecked, range: affected)
                updated.addAttribute(.weaveParagraphStyle, value: "body", range: affected)
                if let bodyFont = attributes[.font] {
                    updated.addAttribute(.font, value: bodyFont, range: affected)
                }
            }
            let nextAttributes: [NSAttributedString.Key: Any]
            switch edit.style {
            case .bold, .italic, .code, .strike: nextAttributes = originalAttributes
            default: nextAttributes = attributes
            }
            // Register the raw typed marker as the undo state: one undo restores syntax,
            // without triggering the shortcut again through the input delegate.
            let raw = NSMutableAttributedString(attributedString: storage)
            if origin == .markdownShortcut {
                raw.replaceCharacters(
                    in: context.range,
                    with: NSAttributedString(string: context.replacement, attributes: originalAttributes))
            }
            registerUndo(
                text: raw,
                selection: origin == .markdownShortcut
                    ? NSRange(location: context.range.location + context.replacement.utf16.count, length: 0)
                    : context.selection,
                attributes: originalAttributes)
            apply(text: updated, selection: after, attributes: nextAttributes)
            textView.undoManager?.setActionName("Markdown 快捷输入")
        }

        func exitTrailingCode() -> Bool {
            guard !hasMarkedText, let storage, let view = textView, storage.length > 0,
                (storage.attribute(.weaveCodeStyle, at: storage.length - 1, effectiveRange: nil) as? String)?.hasPrefix("block:") == true
            else { return false }
            var body = AttributedString("\n")
            body.font = .body
            body[ParagraphStyleAttribute.self] = "body"
            let boundary = NativeTextAttributes.native(body, context: parent.fontContext)
            let attributes = boundary.attributes(at: 0, effectiveRange: nil)
            registerUndo(
                text: NSAttributedString(attributedString: storage), selection: currentSelection, attributes: view.typingAttributes)
            let next = NSMutableAttributedString(attributedString: storage)
            if next.string.hasSuffix("\n") {
                next.setAttributes(attributes, range: NSRange(location: next.length - 1, length: 1))
            } else {
                next.append(boundary)
            }
            apply(text: next, selection: NSRange(location: next.length, length: 0), attributes: attributes)
            view.undoManager?.setActionName("退出代码块")
            return true
        }

        fileprivate func exitEmptyQuote() -> Bool {
            guard !hasMarkedText, let storage, let view = textView,
                storage.length == 0,
                currentSelection == NSRange(location: 0, length: 0),
                view.typingAttributes[.weaveQuote] as? Bool == true
            else { return false }
            var body = AttributedString(" ")
            body.font = .body
            body[ParagraphStyleAttribute.self] = "body"
            var attributes = NativeTextAttributes.native(body, context: parent.fontContext).attributes(at: 0, effectiveRange: nil)
            attributes.removeValue(forKey: .weaveQuote)
            attributes.removeValue(forKey: .weaveQuoteColor)
            registerUndo(
                text: NSAttributedString(attributedString: storage), selection: currentSelection, attributes: view.typingAttributes)
            apply(text: NSAttributedString(attributedString: storage), selection: currentSelection, attributes: attributes)
            view.undoManager?.setActionName("退出引用")
            return true
        }

        fileprivate func toggleTask(at index: Int) -> Bool {
            guard !hasMarkedText, let storage, let view = textView, index < storage.length else { return false }
            let source = storage.string as NSString
            let paragraph = source.paragraphRange(for: NSRange(location: index, length: 0))
            guard let layout = view.layoutManager as? CodeLayoutManager,
                let markerIndex = layout.taskMarkerIndex(in: paragraph), index == markerIndex
            else { return false }
            let checked = storage.attribute(.weaveTaskChecked, at: markerIndex, effectiveRange: nil) as? Bool ?? false
            registerUndo(
                text: NSAttributedString(attributedString: storage), selection: currentSelection, attributes: view.typingAttributes)
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
                let checked = view.typingAttributes[.weaveTaskChecked] as? Bool
            else { return false }
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

        private func registerUndo(text: NSAttributedString, selection: NSRange, attributes: [NSAttributedString.Key: Any]) {
            textView?.undoManager?.registerUndo(withTarget: self) { coordinator in
                // UndoManager calls the registered target on the AppKit main
                // thread; the closure signature does not express that isolation.
                MainActor.assumeIsolated {
                    guard let current = coordinator.storage, let view = coordinator.textView else { return }
                    coordinator.registerUndo(
                        text: NSAttributedString(attributedString: current), selection: coordinator.currentSelection,
                        attributes: view.typingAttributes)
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
            let role =
                attributes[.weaveParagraphStyle] as? String
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
                lastNativeValue.length > 0
            else { return }
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

        private var quoteDecorationView: QuoteDecorationView?
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
                let container = textContainer
            else {
                return nil
            }
            if paragraph.location < (textStorage?.length ?? 0),
                textStorage?.attribute(.weaveQuote, at: paragraph.location, effectiveRange: nil) as? Bool == true
            {
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
                let container = textContainer
            else { return nil }
            if paragraph.location < (textStorage?.length ?? 0),
                layout.taskMarkerIndex(in: paragraph) != nil
            {
                return nil
            }
            let font =
                typingAttributes[.font] as? NSFont
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
                layout.emptyLineHeadIndent =
                    string.isEmpty
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
                let rect = emptyTaskMarkerDrawingRect()
            else { return }
            layout.drawTaskMarker(
                checked: typingAttributes[.weaveTaskChecked] as? Bool ?? false,
                hovered: isHoveringEmptyTask,
                in: rect
            )
        }
        private func drawQuoteDecorations() {
            guard let layout = layoutManager as? CodeLayoutManager,
                let container = textContainer
            else { return }
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
        override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
            guard let storage = textStorage, let layout = layoutManager as? CodeLayoutManager else { return nil }
            let source = storage.string as NSString
            var actions: [NSAccessibilityCustomAction] = []
            var location = 0
            while location < storage.length {
                let paragraph = source.paragraphRange(for: NSRange(location: location, length: 0))
                if let marker = layout.taskMarkerIndex(in: paragraph) {
                    let checked = storage.attribute(.weaveTaskChecked, at: marker, effectiveRange: nil) as? Bool ?? false
                    let text = source.substring(with: paragraph).trimmingCharacters(in: .whitespacesAndNewlines)
                    let name = checked ? "将“\(text)”标记为未完成" : "将“\(text)”标记为已完成"
                    actions.append(
                        NSAccessibilityCustomAction(name: name) { [weak self] in
                            self?.toggleTask?(marker) ?? false
                        })
                }
                let next = NSMaxRange(paragraph)
                if next <= location { break }
                location = next
            }
            return actions.isEmpty ? nil : actions
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
                let rect = emptyTaskMarkerDrawingRect()
            {
                addCursorRect(layout.taskMarkerHitRect(for: rect), cursor: .pointingHand)
            }
            guard let layout = layoutManager as? CodeLayoutManager, let container = textContainer,
                let storage = textStorage, storage.length > 0
            else { return }
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
                let marker = emptyTaskMarkerDrawingRect()
            else { return false }
            let point = convert(event.locationInWindow, from: nil)
            return layout.taskMarkerHitRect(for: marker).contains(point)
        }
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                event.charactersIgnoringModifiers == "k", selectedRange().length > 0
            {
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
                        code.hasPrefix("block:")
                    {
                        let glyphs = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                        if local.y > layout.codeBackgroundRect(forGlyphRange: glyphs, in: textContainer).maxY,
                            exitTrailingCode?() == true
                        {
                            window?.makeFirstResponder(self)
                            needsDisplay = true
                            return
                        }
                    }
                }
                if let layout = layoutManager as? CodeLayoutManager,
                    let marker = layout.taskMarkerCharacter(at: local, in: textContainer),
                    toggleTask?(marker) == true
                {
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
                    source.substring(with: paragraph).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                {
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
            if selector == #selector(NSResponder.deleteBackward(_:)),
                textView.string.isEmpty,
                textView.selectedRange() == NSRange(location: 0, length: 0)
            {
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
            let affected = pendingNativeEditRange
            pendingNativeEditRange = nil
            publish(around: affected)
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
            if selectedRange.length == 0,
                source.substring(with: paragraph).trimmingCharacters(in: .newlines).isEmpty,
                typingAttributes[.weaveQuote] as? Bool == true,
                paragraph.location >= textStorage.length
                    || textStorage.attribute(.weaveQuote, at: paragraph.location, effectiveRange: nil) as? Bool != true,
                let layout = layoutManager as? CodeLayoutManager
            {
                let font = typingAttributes[.font] as? UIFont ?? .systemFont(ofSize: DocumentTypography.bodySize)
                UIColor.label.withAlphaComponent(0.22).setFill()
                layout.fill(
                    layout.emptyQuoteBarRect(at: insertion, font: font, in: textContainer).offsetBy(
                        dx: textContainerInset.left,
                        dy: textContainerInset.top
                    ), radius: 1)
            }
            if let layout = layoutManager as? CodeLayoutManager,
                let marker = emptyTaskMarkerDrawingRect()
            {
                layout.drawTaskMarker(
                    checked: typingAttributes[.weaveTaskChecked] as? Bool ?? false,
                    hovered: false,
                    in: marker
                )
            }
        }
        var refreshTables: (() -> Void)?
        var toggleTask: ((Int) -> Bool)?
        var toggleEmptyTask: (() -> Bool)?
        private func emptyTaskMarkerDrawingRect() -> CGRect? {
            let source = text as NSString
            let insertion = min(selectedRange.location, source.length)
            let paragraph = source.paragraphRange(for: NSRange(location: insertion, length: 0))
            guard selectedRange.length == 0,
                source.substring(with: paragraph).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                typingAttributes[.weaveParagraphStyle] as? String == "task",
                typingAttributes[.weaveTaskChecked] is Bool,
                let layout = layoutManager as? CodeLayoutManager
            else { return nil }
            if paragraph.location < textStorage.length, layout.taskMarkerIndex(in: paragraph) != nil { return nil }
            let font =
                typingAttributes[.font] as? UIFont
                ?? .systemFont(ofSize: DocumentTypography.bodySize * DocumentTypography.readingScale)
            return layout.emptyTaskMarkerRect(
                at: insertion,
                font: font,
                quoted: typingAttributes[.weaveQuote] as? Bool == true,
                in: textContainer
            ).offsetBy(dx: textContainerInset.left, dy: textContainerInset.top)
        }
        @objc func tappedTask(_ recognizer: UITapGestureRecognizer) {
            let point = recognizer.location(in: self)
            if let layout = layoutManager as? CodeLayoutManager,
                let marker = emptyTaskMarkerDrawingRect(),
                layout.taskMarkerHitRect(for: marker).contains(point)
            {
                _ = toggleEmptyTask?()
                setNeedsDisplay()
                return
            }
            let local = CGPoint(x: point.x - textContainerInset.left, y: point.y - textContainerInset.top)
            guard let layout = layoutManager as? CodeLayoutManager,
                let marker = layout.taskMarkerCharacter(at: local, in: textContainer)
            else { return }
            _ = toggleTask?(marker)
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard gestureRecognizer is UITapGestureRecognizer,
                let layout = layoutManager as? CodeLayoutManager
            else { return true }
            let point = touch.location(in: self)
            if let marker = emptyTaskMarkerDrawingRect(), layout.taskMarkerHitRect(for: marker).contains(point) {
                return true
            }
            let local = CGPoint(x: point.x - textContainerInset.left, y: point.y - textContainerInset.top)
            return layout.taskMarkerCharacter(at: local, in: textContainer) != nil
        }

        private func refreshTaskAccessibilityActions() {
            let source = textStorage.string as NSString
            guard textStorage.length > 0, let layout = layoutManager as? CodeLayoutManager else {
                accessibilityCustomActions = nil
                return
            }
            var actions: [UIAccessibilityCustomAction] = []
            var location = 0
            while location < textStorage.length {
                let paragraph = source.paragraphRange(for: NSRange(location: location, length: 0))
                if let marker = layout.taskMarkerIndex(in: paragraph) {
                    let checked = textStorage.attribute(.weaveTaskChecked, at: marker, effectiveRange: nil) as? Bool ?? false
                    let text = source.substring(with: paragraph).trimmingCharacters(in: .whitespacesAndNewlines)
                    let name = checked ? "将“\(text)”标记为未完成" : "将“\(text)”标记为已完成"
                    actions.append(
                        UIAccessibilityCustomAction(name: name) { [weak self] _ in
                            self?.toggleTask?(marker) ?? false
                        })
                }
                let next = NSMaxRange(paragraph)
                if next <= location { break }
                location = next
            }
            accessibilityCustomActions = actions.isEmpty ? nil : actions
        }

        override func layoutSubviews() {
            let inset = max(24, (bounds.width - DocumentTypography.readingWidth) / 2)
            if textContainerInset.left != inset {
                textContainerInset = UIEdgeInsets(top: DocumentTypography.editorTopInset, left: inset, bottom: 40, right: inset)
            }
            super.layoutSubviews()
            refreshTables?()
            refreshTaskAccessibilityActions()
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
            view.toggleEmptyTask = { [weak coordinator = context.coordinator] in coordinator?.toggleEmptyTask() ?? false }
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
            return intercept(range: range, replacement: text)
        }
        func textViewDidChange(_ textView: UITextView) {
            restoreEmptyQuoteTypingAttributesFromPreviousValue()
            if let attributes = pendingTypingAttributesAfterInlineDeletion {
                textView.typingAttributes = attributes
                pendingTypingAttributesAfterInlineDeletion = nil
            }
            let affected = pendingNativeEditRange
            pendingNativeEditRange = nil
            publish(around: affected)
        }
        func textViewDidChangeSelection(_ textView: UITextView) {
            textView.setNeedsDisplay()
            publishSelection()
        }
    }
#endif
