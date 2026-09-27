import SwiftUI

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

/// Reuses each hosting view across text-storage edits so native cell input keeps focus.
@MainActor
final class TableOverlayController {
    @MainActor private final class Entry {
        let model: NativeTableModel
        #if os(macOS)
            let host: NSHostingView<TableBlockView>
        #else
            let host: UIHostingController<TableBlockView>
        #endif

        init(model: NativeTableModel) {
            self.model = model
            #if os(macOS)
                host = NSHostingView(rootView: TableBlockView(model: model))
            #else
                host = UIHostingController(rootView: TableBlockView(model: model))
                host.view.backgroundColor = .clear
            #endif
        }
    }

    private var entries: [UUID: Entry] = [:]
    private var isRefreshing = false

    func refresh(
        in textView: PlatformTextView,
        onChange: @escaping (UUID, TableData) -> Void,
        onExit: @escaping (Int) -> Void
    ) {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        #if os(macOS)
            guard let storage = textView.textStorage, let layout = textView.layoutManager,
                let container = textView.textContainer
            else { return }
            let origin = textView.textContainerOrigin
        #else
            let storage = textView.textStorage
            let layout = textView.layoutManager
            let container = textView.textContainer
            let origin = CGPoint(x: textView.textContainerInset.left, y: textView.textContainerInset.top)
        #endif
        var validIDs: Set<UUID> = []
        storage.enumerateAttribute(NSAttributedString.Key(TableAttribute.name), in: NSRange(location: 0, length: storage.length)) {
            value, range, _ in
            guard let data = value as? Data, let table = try? JSONDecoder().decode(TableData.self, from: data),
                !validIDs.contains(table.id)
            else { return }
            validIDs.insert(table.id)
            let entry: Entry
            if let existing = self.entries[table.id] {
                entry = existing
                if entry.model.table != table { entry.model.table = table }
            } else {
                entry = Entry(model: NativeTableModel(table: table, onChange: { _ in }, onExit: {}))
                self.entries[table.id] = entry
                #if os(macOS)
                    textView.addSubview(entry.host)
                #else
                    textView.addSubview(entry.host.view)
                #endif
            }
            entry.model.onChange = { onChange(table.id, $0) }
            entry.model.onExit = { onExit(NSMaxRange(range)) }
            let glyphs = layout.glyphRange(forCharacterRange: NSRange(location: range.location, length: 1), actualCharacterRange: nil)
            let bounds = layout.boundingRect(forGlyphRange: glyphs, in: container)
            let frame = CGRect(
                x: origin.x + container.lineFragmentPadding, y: origin.y + bounds.minY,
                width: max(1, container.size.width - 2 * container.lineFragmentPadding),
                height: TableTextAttachment.height(for: table)
            )
            #if os(macOS)
                if entry.host.frame != frame { entry.host.frame = frame }
            #else
                if entry.host.view.frame != frame { entry.host.view.frame = frame }
            #endif
        }
        for id in Set(entries.keys).subtracting(validIDs) {
            #if os(macOS)
                entries[id]?.host.removeFromSuperview()
            #else
                entries[id]?.host.view.removeFromSuperview()
            #endif
            entries.removeValue(forKey: id)
        }
    }
}

enum CodeCopyStatus {
    case ready, copied, failed

    var symbol: String {
        switch self {
        case .ready: "doc.on.doc"
        case .copied: "checkmark"
        case .failed: "exclamationmark.triangle"
        }
    }

    var label: String {
        switch self {
        case .ready: "复制代码"
        case .copied: "已复制代码"
        case .failed: "复制失败，点击重试"
        }
    }

    var color: Color {
        switch self {
        case .ready: .secondary
        case .copied: .green
        case .failed: .red
        }
    }
}

@Observable @MainActor
final class CodeHeaderModel {
    var language = ""
    var literal = "" {
        didSet {
            guard literal != oldValue else { return }
            copyStatus = .ready
            copyAttempt += 1
        }
    }
    var onLanguage: (String) -> Void = { _ in }
    var onFormat: () async throws -> Void = {}
    var formatRequest = 0
    var isFormatting = false
    var onToast: (ToastMessage) -> Void = { _ in }
    var canFormat: Bool { CodeFormatting.parser(for: language) != nil }

    var isExpanded = false
    var canExpand = false
    var onExpand: (Bool) -> Void = { _ in }
    var wrapsCode = true
    var onWrap: (Bool) -> Void = { _ in }
    private(set) var copyStatus = CodeCopyStatus.ready
    private(set) var copyAttempt = 0
    @ObservationIgnored var writeClipboard: (String) -> Bool = { text in
        #if os(macOS)
            NSPasteboard.general.clearContents()
            return NSPasteboard.general.setString(text, forType: .string)
        #else
            // UIKit's local pasteboard write has no failure result to inspect.
            UIPasteboard.general.string = text
            return true
        #endif
    }

    func copyCode() {
        copyStatus = writeClipboard(literal) ? .copied : .failed
        copyAttempt += 1
        if copyStatus == .failed {
            onToast(ToastMessage(title: "复制失败", message: "未能写入剪贴板，请重试。"))
        }
    }

    func reportFormatFailure(_ error: Error) {
        let message: String
        switch error {
        case CodeFormatting.Failure.changed: message = "代码或语言已修改，请重新格式化。"
        case CodeFormatting.Failure.tooLarge: message = "代码过长，暂不支持格式化。"
        case CodeFormatting.Failure.syntax: message = "请检查代码语法，原文已保留。"
        default: message = "未能完成格式化，原文已保留。"
        }
        onToast(ToastMessage(title: "格式化失败", message: message, details: error.localizedDescription))
    }

    func resetCopyFeedback() { copyStatus = .ready }
}

struct CodeHeaderView: View {
    @Bindable var model: CodeHeaderModel

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Menu {
                ForEach(CodeBlockEditing.languages, id: \.id) { language in
                    Button(language.title) { model.onLanguage(language.id) }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(
                        CodeBlockEditing.languages.first { $0.id == CodeBlockEditing.canonicalLanguage(model.language) }?.title
                            ?? model.language)
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                }
                .frame(height: CodeLayoutManager.headerHeight, alignment: .topLeading)
                .contentShape(Rectangle())
            }
            .menuIndicator(.hidden)
            .accessibilityLabel("代码语言")
            .accessibilityIdentifier("code-language")
            #if os(macOS)
                .pointerStyle(.link)
                .background(CodeHeaderPointerRegion())
            #endif
            Spacer()
            if model.canExpand || model.isExpanded {
                Button {
                    model.onExpand(!model.isExpanded)
                } label: {
                    Image(systemName: model.isExpanded ? "chevron.up" : "chevron.down")
                        .resizable().scaledToFit()
                        .frame(width: 12, height: 12)
                        .frame(width: 14, height: 14)
                        .frame(width: 28, height: CodeLayoutManager.headerHeight, alignment: .topTrailing)
                        .contentShape(Rectangle())
                }
                .help(model.isExpanded ? "收起" : "展开全部")
                .accessibilityLabel(model.isExpanded ? "收起" : "展开全部")
                .accessibilityIdentifier("code-expand")
                #if os(macOS)
                    .pointerStyle(.link)
                    .background(CodeHeaderPointerRegion())
                #endif
            }
            Button {
                model.onWrap(!model.wrapsCode)
            } label: {
                Image(systemName: "return")
                    .resizable().scaledToFit()
                    .frame(width: 12, height: 12)
                    .frame(width: 14, height: 14)
                    .foregroundStyle(model.wrapsCode ? Color.accentColor : Color.secondary)
                    .frame(width: 28, height: CodeLayoutManager.headerHeight, alignment: .topTrailing)
                    .contentShape(Rectangle())
            }
            .help(model.wrapsCode ? "关闭自动换行" : "开启自动换行")
            .accessibilityLabel("自动换行")
            .accessibilityValue(model.wrapsCode ? "开启" : "关闭")
            .accessibilityIdentifier("code-wrap")
            #if os(macOS)
                .pointerStyle(.link)
                .background(CodeHeaderPointerRegion())
            #endif
            if model.canFormat {
                Button {
                    model.isFormatting = true
                    model.formatRequest += 1
                } label: {
                    Image(systemName: "text.alignleft")
                        .resizable().scaledToFit()
                        .frame(width: 14, height: 14)
                        .frame(width: 28, height: CodeLayoutManager.headerHeight, alignment: .topTrailing)
                        .contentShape(Rectangle())
                }
                .disabled(model.isFormatting)
                .help(model.isFormatting ? "正在格式化…" : "格式化代码")
                .accessibilityLabel("格式化代码")
                .accessibilityIdentifier("format-code")
                #if os(macOS)
                    .pointerStyle(.link)
                    .background(CodeHeaderPointerRegion())
                #endif
            }
            Button {
                model.copyCode()
            } label: {
                Image(systemName: model.copyStatus.symbol)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 14, height: 14)
                    .foregroundStyle(model.copyStatus.color)
                    .frame(width: 28, height: CodeLayoutManager.headerHeight, alignment: .topTrailing)
                    .contentShape(Rectangle())
            }
            .help(model.copyStatus.label)
            .accessibilityLabel(model.copyStatus.label)
            .accessibilityIdentifier("copy-code")
            #if os(macOS)
                .pointerStyle(.link)
                .background(CodeHeaderPointerRegion())
            #endif
        }
        .font(.system(size: DocumentTypography.controlFontSize))
        .foregroundStyle(.secondary)
        .buttonStyle(.plain)
        #if os(macOS)
            .menuStyle(.button)
        #endif
        .padding(.horizontal, DocumentTypography.codeInset)
        .frame(height: CodeLayoutManager.headerHeight)
        .task(id: model.formatRequest) {
            guard model.formatRequest > 0, model.isFormatting else { return }
            defer { model.isFormatting = false }
            do {
                try await model.onFormat()
            } catch is CancellationError {
                // Removing the header cancels its request without publishing stale text.
            } catch {
                guard !Task.isCancelled else { return }
                model.reportFormatFailure(error)
            }
        }
        .task(id: model.copyAttempt) {
            guard model.copyStatus != .ready else { return }
            do {
                try await Task.sleep(for: .seconds(2))
            } catch { return }
            guard !Task.isCancelled else { return }
            model.resetCopyFeedback()
        }
    }
}

#if os(macOS)
    /// Supplies AppKit cursor geometry without intercepting the SwiftUI control's clicks.
    private struct CodeHeaderPointerRegion: NSViewRepresentable {
        func makeNSView(context: Context) -> CodeHeaderPointerView { CodeHeaderPointerView() }
        func updateNSView(_ nsView: CodeHeaderPointerView, context: Context) {}
    }

    private final class CodeHeaderPointerView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func resetCursorRects() {
            super.resetCursorRects()
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }

    final class CodeHeaderHostingView: NSHostingView<CodeHeaderView> {
        func cursor(at point: NSPoint) -> NSCursor {
            func containsControl(_ view: NSView) -> Bool {
                guard !view.isHidden else { return false }
                if view is CodeHeaderPointerView {
                    return view.bounds.contains(view.convert(point, from: self))
                }
                return view.subviews.contains(where: containsControl)
            }
            return containsControl(self) ? .pointingHand : .arrow
        }

        override func cursorUpdate(with event: NSEvent) {
            cursor(at: convert(event.locationInWindow, from: nil)).set()
        }
    }
#endif

/// Only the header is hosted; code remains in the document's native text storage.
@MainActor
final class CodeHeaderOverlayController {
    @MainActor private final class Entry {
        let model = CodeHeaderModel()
        #if os(macOS)
            let host: NSHostingView<CodeHeaderView>
        #else
            let host: UIHostingController<CodeHeaderView>
        #endif
        init() {
            #if os(macOS)
                host = CodeHeaderHostingView(rootView: CodeHeaderView(model: model))
            #else
                host = UIHostingController(rootView: CodeHeaderView(model: model))
                host.view.backgroundColor = .clear
            #endif
        }
    }
    private var entries: [String: Entry] = [:]
    private var isRefreshing = false

    func refresh(
        in textView: PlatformTextView,
        onLanguage: @escaping (String, String) -> Void,
        onFormat: @escaping (String) async throws -> Void = { _ in },
        onToast: @escaping (ToastMessage) -> Void = { _ in }
    ) {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        #if os(macOS)
            guard let storage = textView.textStorage, let layout = textView.layoutManager,
                let container = textView.textContainer
            else { return }
            let origin = textView.textContainerOrigin
        #else
            let storage = textView.textStorage
            let layout = textView.layoutManager
            let container = textView.textContainer
            let origin = CGPoint(x: textView.textContainerInset.left, y: textView.textContainerInset.top)
        #endif
        (layout as? CodeLayoutManager)?.clampCodeViewports(in: container)
        var validIDs: Set<String> = []
        storage.enumerateAttribute(.weaveCodeStyle, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard let id = value as? String, id.hasPrefix("block:"), !validIDs.contains(id) else { return }
            validIDs.insert(id)
            let entry: Entry
            if let existing = entries[id] {
                entry = existing
            } else {
                entry = Entry()
                entries[id] = entry
                #if os(macOS)
                    textView.addSubview(entry.host)
                #else
                    textView.addSubview(entry.host.view)
                #endif
            }
            entry.model.language = storage.attribute(.weaveCodeLanguage, at: range.location, effectiveRange: nil) as? String ?? ""
            var literal = (storage.string as NSString).substring(with: range)
            if literal.hasSuffix("\n"), NSMaxRange(range) < storage.length { literal.removeLast() }
            entry.model.literal = literal
            entry.model.onLanguage = { onLanguage(id, $0) }
            entry.model.onFormat = { try await onFormat(id) }
            entry.model.onToast = onToast
            if let codeLayout = layout as? CodeLayoutManager {
                codeLayout.updateCodeWidth(id: id, range: range, in: container)
                codeLayout.ensureLayout(for: container)
                entry.model.isExpanded = codeLayout.expandedCode.contains(id)
                entry.model.canExpand = codeLayout.canExpandCode(id: id)
                entry.model.onExpand = { [weak self, weak textView, weak codeLayout] expanded in
                    guard let self, let textView, let codeLayout else { return }
                    #if os(macOS)
                        let scrollView = textView.enclosingScrollView
                        let scrollOrigin = scrollView?.contentView.bounds.origin
                    #else
                        let scrollOrigin = textView.contentOffset
                    #endif
                    codeLayout.setCodeExpanded(expanded, id: id, in: container)
                    #if os(macOS)
                        textView.needsDisplay = true
                    #else
                        textView.setNeedsDisplay()
                    #endif
                    self.refresh(in: textView, onLanguage: onLanguage, onFormat: onFormat, onToast: onToast)
                    // Resizing the native document must not scroll the clicked
                    // header out of view when its code expands beneath it.
                    #if os(macOS)
                        textView.layoutSubtreeIfNeeded()
                        if let scrollView, let scrollOrigin {
                            scrollView.contentView.scroll(to: scrollOrigin)
                            scrollView.reflectScrolledClipView(scrollView.contentView)
                        }
                    #else
                        textView.layoutIfNeeded()
                        textView.setContentOffset(scrollOrigin, animated: false)
                    #endif
                }
                entry.model.wrapsCode = !codeLayout.unwrappedCode.contains(id)
                entry.model.onWrap = { [weak self, weak textView, weak codeLayout] wraps in
                    guard let self, let textView, let codeLayout else { return }
                    codeLayout.setCodeWrapping(wraps, id: id)
                    codeLayout.ensureLayout(for: container)
                    #if os(macOS)
                        textView.needsDisplay = true
                    #else
                        textView.setNeedsDisplay()
                    #endif
                    self.refresh(in: textView, onLanguage: onLanguage, onFormat: onFormat, onToast: onToast)
                }
            }
            let glyphs = layout.glyphRange(forCharacterRange: NSRange(location: range.location, length: 1), actualCharacterRange: nil)
            let bounds = layout.lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
            // The header shares the code surface's quote offset; its SwiftUI
            // content supplies only the padding inside that surface.
            let quoteInset =
                storage.attribute(.weaveQuote, at: range.location, effectiveRange: nil) as? Bool == true
                ? DocumentTypography.quoteIndent : 0
            let frame = CGRect(
                x: origin.x + container.lineFragmentPadding + quoteInset,
                y: origin.y + ((layout as? CodeLayoutManager)?.codeHeaderY(forGlyph: glyphs.location) ?? bounds.minY),
                width: max(1, container.size.width - 2 * container.lineFragmentPadding - quoteInset),
                height: CodeLayoutManager.headerHeight)
            #if os(macOS)
                if entry.host.frame != frame { entry.host.frame = frame }
            #else
                if entry.host.view.frame != frame { entry.host.view.frame = frame }
            #endif
        }
        for id in Set(entries.keys).subtracting(validIDs) {
            #if os(macOS)
                entries[id]?.host.removeFromSuperview()
            #else
                entries[id]?.host.view.removeFromSuperview()
            #endif
            entries.removeValue(forKey: id)
        }
    }
}
