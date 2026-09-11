import SwiftUI

struct WorkspaceView: View {
    @Bindable var store: NoteStore
    @State private var query = ""
    @State private var compactColumn: NavigationSplitViewColumn = .sidebar

    private var visibleNotes: [Note] {
        store.notes.filter { query.isEmpty || $0.text.localizedStandardContains(query) }
    }

    var body: some View {
        NavigationSplitView(preferredCompactColumn: $compactColumn) {
            List(selection: $store.selectedID) {
                ForEach(visibleNotes) { note in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(note.title)
                            .font(.headline)
                            .lineLimit(1)
                        Text(note.preview.isEmpty ? "暂无正文" : note.preview)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .padding(.vertical, 6)
                    .tag(note.id)
                }
            }
            .overlay {
                if !query.isEmpty && visibleNotes.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .navigationTitle("记录")
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
            .searchable(text: $query, prompt: "搜索记录")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("新建记录", systemImage: "square.and.pencil") {
                        query = ""
                        store.createNote()
                    }
                    .disabled(store.loadError != nil)
                    .accessibilityIdentifier("new-note")
                    .help("新建记录")
                }
            }
        } detail: {
            if let error = store.loadError {
                ContentUnavailableView {
                    Label("无法读取记录", systemImage: "exclamationmark.triangle")
                } description: {
                    Text("原文件已保留。\n\(error)")
                } actions: {
                    Button("重新读取") { store.reload() }
                }
            } else if let note = store.notes.first(where: { $0.id == store.selectedID }) {
                NoteEditorView(
                    note: note,
                    store: store,
                    saveError: store.saveError,
                    retrySave: store.retrySave
                )
                .id(note.id)
            } else {
                ContentUnavailableView {
                    Label("从一条记录开始", systemImage: "square.and.pencil")
                } description: {
                    Text("写下此刻的想法。")
                } actions: {
                    Button("新建记录", systemImage: "plus") { store.createNote() }
                        .buttonStyle(.glassProminent)
                }
            }
        }
        .onChange(of: store.selectedID) { _, selectedID in
            guard let selectedID else { return }
            if !visibleNotes.contains(where: { $0.id == selectedID }) {
                query = ""
            }
            compactColumn = .detail
        }
        #if os(macOS)
        .frame(minWidth: 650, minHeight: 420)
        #endif
    }
}

private struct NoteEditorView: View {
    let note: Note
    @Bindable var store: NoteStore
    let saveError: String?
    let retrySave: () -> Void
    @FocusState private var isFocused: Bool
    @State private var selection = AttributedTextSelection()
    @State private var showsMarkdownHelp = false
    @State private var showsLinkEditor = false
    @State private var linkAddress = ""
    @Environment(\.undoManager) private var undoManager
    @Environment(\.fontResolutionContext) private var fontContext

    private var richText: AttributedString {
        store.notes.first(where: { $0.id == note.id })?.richText ?? AttributedString()
    }

    var body: some View {
        NativeRichTextEditor(text: Binding(
            get: { richText },
            set: { store.updateRichText(id: note.id, text: $0) }
        ), selection: $selection, onEditLink: {
            linkAddress = selection.attributes(in: richText).compactMap { $0.link?.absoluteString }.first ?? ""
            showsLinkEditor = true
        })
            .font(.body)
            .frame(maxWidth: .infinity)
            .focused($isFocused)
            .accessibilityLabel("记录正文")
            .navigationTitle(note.title)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Menu("格式", systemImage: "textformat") {
                        Button(formatLabel("加粗") { ($0.font ?? .body).resolve(in: fontContext).isBold }, systemImage: "bold") { toggleBold() }
                            .keyboardShortcut("b", modifiers: .command)
                        Button(formatLabel("斜体") { ($0.font ?? .body).resolve(in: fontContext).isItalic }, systemImage: "italic") { toggleItalic() }
                            .keyboardShortcut("i", modifiers: .command)
                        Button(formatLabel("下划线") { $0.underlineStyle != nil }, systemImage: "underline") {
                            format { $0.underlineStyle = $0.underlineStyle == nil ? .single : nil }
                        }
                            .keyboardShortcut("u", modifiers: .command)
                        Button(formatLabel("删除线") { $0.strikethroughStyle != nil }, systemImage: "strikethrough") {
                            format { $0.strikethroughStyle = $0.strikethroughStyle == nil ? .single : nil }
                        }
                        Divider()
                        Button("一级标题") { paragraph("heading:1") }
                        Button("二级标题") { paragraph("heading:2") }
                        Button("三级标题") { paragraph("heading:3") }
                        Button("正文") { paragraph("body") }
                        Button("无序列表") { paragraph("bullet") }
                        Button("有序列表") { paragraph("numbered") }
                        Button("待办列表") { paragraph("task") }
                        Button("引用") { paragraph("quote") }
                        Button("代码块") { paragraph("code") }
                        Button("切换待办完成状态") { toggleTask() }
                            .keyboardShortcut(.return, modifiers: [.command, .shift])
                        Divider()
                        Button("添加或编辑链接…", systemImage: "link") {
                            linkAddress = selection.attributes(in: richText).compactMap { $0.link?.absoluteString }.first ?? ""
                            showsLinkEditor = true
                        }
                        .keyboardShortcut("k", modifiers: .command)
                        .disabled(!hasSelection)
                        Button("移除链接") { format { $0.link = nil } }
                            .disabled(!hasSelection)
                        Button("清除文字格式") {
                            format {
                                $0.font = .body
                                $0.underlineStyle = nil
                                $0.strikethroughStyle = nil
                                $0.foregroundColor = nil
                                $0.backgroundColor = nil
                                $0.link = nil
                                $0[CodeStyleAttribute.self] = nil
                            }
                        }
                        Button("等宽代码", systemImage: "chevron.left.forwardslash.chevron.right") {
                            format { $0.font = .body.monospaced(); $0[CodeStyleAttribute.self] = "inline" }
                        }
                    }
                    .accessibilityLabel("格式")
                    .help("设置文字格式")
                    Menu("Markdown", systemImage: "text.badge.checkmark") {
                        Button("将选区 Markdown 排版") { convertMarkdown(wholeDocument: false) }
                            .disabled(!hasSelection)
                        Button("将全文 Markdown 排版") { convertMarkdown(wholeDocument: true) }
                            .disabled(richText.characters.isEmpty)
                        Divider()
                        Button("支持的语法") { showsMarkdownHelp = true }
                    }
                    .accessibilityLabel("Markdown")
                    .help("将 Markdown 转换为富文本")
                }
                ToolbarItem(placement: .automatic) {
                    Text("\(richText.characters.count) 字符")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .sheet(isPresented: $showsLinkEditor) {
                NavigationStack {
                    Form {
                        TextField("链接地址", text: $linkAddress)
                        Text("输入完整的 https://、http:// 或 mailto: 地址。")
                            .foregroundStyle(.secondary)
                    }
                    .navigationTitle("编辑链接")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("取消") { showsLinkEditor = false } }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("保存") {
                                guard let url = validatedLink else { return }
                                format { $0.link = url }
                                showsLinkEditor = false
                            }.disabled(validatedLink == nil)
                        }
                    }
                }
                #if os(macOS)
                .frame(width: 440, height: 180)
                #endif
            }
            .sheet(isPresented: $showsMarkdownHelp) {
                NavigationStack {
                    List {
                        Section("输入时自动排版，可撤销") {
                            Text("行首输入 # 至 ######、-、*、+、> 后按空格。")
                            Text("输入 **加粗**、*斜体*、`代码` 的闭合标记后自动转换。")
                            Text("列表和引用按回车续行，空行再按回车退出。")
                        }
                        Section("更多语法：从 Markdown 菜单选择排版") {
                            Text("# 大标题\n## 标题\n### 小标题")
                            Text("**加粗**  *斜体*  ~~删除线~~")
                            Text("`行内代码`  [链接](https://example.com)")
                            Text("- 列表\n1. 有序列表\n> 引用")
                            Text("- [ ] 未完成\n- [x] 已完成")
                            Text("```\n代码块\n```")
                        }
                        Section {
                            Text("勾选项可点击切换，不关联独立待办。列表支持基本缩进，尚不支持结构化重排和自动重编号。不支持表格、图片或富文本到 Markdown 的无损往返。")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .navigationTitle("Markdown 语法")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("完成") { showsMarkdownHelp = false }
                        }
                    }
                }
                #if os(macOS)
                .frame(width: 520, height: 540)
                #endif
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let saveError {
                    HStack {
                        Label("尚未保存：\(saveError)", systemImage: "exclamationmark.triangle")
                            .font(.callout)
                            .textSelection(.enabled)
                        Spacer()
                        Button("重试", action: retrySave)
                    }
                    .padding()
                    .background(.regularMaterial)
                }
            }
            .task {
                if richText.characters.isEmpty { isFocused = true }
            }
    }

    private func formatLabel(_ title: String, matches: (AttributeContainer) -> Bool) -> String {
        let values = selection.attributes(in: richText).map(matches)
        guard !values.isEmpty else { return title }
        if values.allSatisfy({ $0 }) { return "✓ " + title }
        if values.contains(true) { return title + "（混合）" }
        return title
    }

    private var validatedLink: URL? {
        guard let url = URL(string: linkAddress.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }

    private func paragraph(_ style: String) {
        var updated = richText
        ParagraphEditing.apply(style, to: &updated, selection: &selection)
        store.applyRichEdit(id: note.id, text: updated, undoManager: undoManager)
        isFocused = true
    }

    private func toggleTask() {
        var updated = richText
        ParagraphEditing.toggleTask(in: &updated, selection: &selection)
        store.applyRichEdit(id: note.id, text: updated, undoManager: undoManager)
    }

    private var hasSelection: Bool {
        if case .ranges(let ranges) = selection.indices(in: richText) { return ranges.ranges.count == 1 }
        return false
    }

    private func format(_ change: (inout AttributeContainer) -> Void) {
        var updated = richText
        updated.transformAttributes(in: &selection, body: change)
        store.applyRichEdit(id: note.id, text: updated, undoManager: undoManager)
        isFocused = true
    }

    private func toggleBold() {
        let fonts = selection.attributes(in: richText).map { $0.font ?? .body }
        let remove = !fonts.isEmpty && fonts.allSatisfy { $0.resolve(in: fontContext).isBold }
        format { $0.font = ($0.font ?? .body).bold(!remove) }
    }

    private func toggleItalic() {
        let fonts = selection.attributes(in: richText).map { $0.font ?? .body }
        let remove = !fonts.isEmpty && fonts.allSatisfy { $0.resolve(in: fontContext).isItalic }
        format { $0.font = ($0.font ?? .body).italic(!remove) }
    }

    private func convertMarkdown(wholeDocument: Bool) {
        var updated = richText
        if wholeDocument {
            updated = MarkdownFormatting.render(String(updated.characters))
            selection = AttributedTextSelection(insertionPoint: updated.endIndex)
        } else {
            guard case .ranges(let ranges) = selection.indices(in: updated),
                  ranges.ranges.count == 1, let range = ranges.ranges.first else { return }
            let source = String(updated[range].characters)
            updated.replaceSelection(&selection, with: MarkdownFormatting.render(source))
        }
        store.applyRichEdit(id: note.id, text: updated, undoManager: undoManager)
        isFocused = true
    }
}
