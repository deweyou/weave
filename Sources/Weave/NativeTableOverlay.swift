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
              let container = textView.textContainer else { return }
        let origin = textView.textContainerOrigin
        #else
        let storage = textView.textStorage
        let layout = textView.layoutManager
        let container = textView.textContainer
        let origin = CGPoint(x: textView.textContainerInset.left, y: textView.textContainerInset.top)
        #endif
        var validIDs: Set<UUID> = []
        storage.enumerateAttribute(NSAttributedString.Key(TableAttribute.name), in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard let data = value as? Data, let table = try? JSONDecoder().decode(TableData.self, from: data),
                  !validIDs.contains(table.id) else { return }
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

@Observable @MainActor
final class CodeHeaderModel {
    var language = ""
    var literal = ""
    var onLanguage: (String) -> Void = { _ in }
}

struct CodeHeaderView: View {
    @Bindable var model: CodeHeaderModel
    @State private var copied = false

    var body: some View {
        HStack {
            Menu {
                ForEach(CodeBlockEditing.languages, id: \.id) { language in
                    Button(language.title) { model.onLanguage(language.id) }
                }
            } label: {
                Text(CodeBlockEditing.languages.first { $0.id == model.language }?.title ?? model.language)
            }
            .accessibilityLabel("代码语言")
            .accessibilityIdentifier("code-language")
            Spacer()
            Button {
                #if os(macOS)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(model.literal, forType: .string)
                #else
                UIPasteboard.general.string = model.literal
                #endif
                copied = true
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .frame(width: 28, height: CodeLayoutManager.headerHeight)
            }
            .help(copied ? "已复制" : "复制代码")
            .accessibilityLabel(copied ? "已复制代码" : "复制代码")
            .accessibilityIdentifier("copy-code")
        }
        .font(.system(size: DocumentTypography.controlFontSize))
        .foregroundStyle(.secondary)
        .buttonStyle(.borderless)
        #if os(macOS)
        .menuStyle(.borderlessButton)
        #endif
        .padding(.horizontal, DocumentTypography.codeInset)
        .frame(height: CodeLayoutManager.headerHeight)
        .onChange(of: model.literal) { _, _ in copied = false }
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            copied = false
        }
    }
}

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
            host = NSHostingView(rootView: CodeHeaderView(model: model))
            #else
            host = UIHostingController(rootView: CodeHeaderView(model: model))
            host.view.backgroundColor = .clear
            #endif
        }
    }
    private var entries: [String: Entry] = [:]
    private var isRefreshing = false

    func refresh(in textView: PlatformTextView, onLanguage: @escaping (String, String) -> Void) {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        #if os(macOS)
        guard let storage = textView.textStorage, let layout = textView.layoutManager,
              let container = textView.textContainer else { return }
        let origin = textView.textContainerOrigin
        #else
        let storage = textView.textStorage
        let layout = textView.layoutManager
        let container = textView.textContainer
        let origin = CGPoint(x: textView.textContainerInset.left, y: textView.textContainerInset.top)
        #endif
        var validIDs: Set<String> = []
        storage.enumerateAttribute(.weaveCodeStyle, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard let id = value as? String, id.hasPrefix("block:"), !validIDs.contains(id) else { return }
            validIDs.insert(id)
            let entry: Entry
            if let existing = entries[id] { entry = existing }
            else {
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
            let glyphs = layout.glyphRange(forCharacterRange: NSRange(location: range.location, length: 1), actualCharacterRange: nil)
            let bounds = layout.lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
            let frame = CGRect(x: origin.x + container.lineFragmentPadding,
                               y: origin.y + bounds.minY,
                               width: max(1, container.size.width - 2 * container.lineFragmentPadding),
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
