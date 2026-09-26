import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

struct WorkspaceView: View {
    @Bindable var store: NoteStore
    var body: some View {
        #if os(macOS)
            MacWorkspaceView(store: store)
        #else
            MobileWorkspaceView(store: store)
        #endif
    }
}

struct RecordGallery<Card: View>: View {
    let notes: [Note]
    @Binding var scrollOffset: CGFloat
    @State private var position = ScrollPosition(y: 0)
    @State private var hasRestoredPosition = false
    @ViewBuilder let card: (Note) -> Card

    private var minimumCardWidth: CGFloat {
        #if os(macOS)
            220
        #else
            160
        #endif
    }

    var body: some View {
        ScrollView {
            RecordMasonryLayout(minimumColumnWidth: minimumCardWidth) {
                ForEach(notes) { note in
                    card(note).id(note.id)
                }
            }
            .padding(20)
        }
        .scrollPosition($position)
        .onAppear {
            position.scrollTo(y: scrollOffset)
            hasRestoredPosition = true
        }
        .onChange(of: scrollOffset) { _, offset in
            if offset == 0 { position.scrollTo(y: 0) }
        }
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            max(0, geometry.contentOffset.y + geometry.contentInsets.top)
        } action: { _, offset in
            if hasRestoredPosition { scrollOffset = offset }
        }
        .accessibilityIdentifier("record-gallery")
    }
}

/// Measures each card at its actual column width, then fills the shortest column.
/// Subviews stay in source order and retain identity when the column count changes.
struct RecordMasonryLayout: Layout {
    var minimumColumnWidth: CGFloat
    var spacing: CGFloat = 16

    func columnCount(for width: CGFloat) -> Int {
        max(1, Int((max(0, width) + spacing) / (minimumColumnWidth + spacing)))
    }

    func columnWidth(for width: CGFloat) -> CGFloat {
        let count = columnCount(for: width)
        return max(0, (width - CGFloat(count - 1) * spacing) / CGFloat(count))
    }

    func frames(for width: CGFloat, heights: [CGFloat]) -> [CGRect] {
        let count = columnCount(for: width)
        let cardWidth = columnWidth(for: width)
        var bottoms = Array(repeating: CGFloat.zero, count: count)
        return heights.map { height in
            // On ties, prefer the leading column to keep placement deterministic.
            let column = bottoms.indices.min { bottoms[$0] < bottoms[$1] } ?? 0
            let frame = CGRect(x: CGFloat(column) * (cardWidth + spacing), y: bottoms[column], width: cardWidth, height: height)
            bottoms[column] = frame.maxY + spacing
            return frame
        }
    }

    private func measuredFrames(width: CGFloat, subviews: Subviews) -> [CGRect] {
        let proposal = ProposedViewSize(width: columnWidth(for: width), height: nil)
        return frames(for: width, heights: subviews.map { $0.sizeThatFits(proposal).height })
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? minimumColumnWidth
        let frames = measuredFrames(width: width, subviews: subviews)
        return CGSize(width: width, height: frames.map(\.maxY).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = measuredFrames(width: bounds.width, subviews: subviews)
        for (subview, frame) in zip(subviews, frames) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                anchor: .topLeading, proposal: ProposedViewSize(frame.size)
            )
        }
    }
}

struct RecordCard: View {
    let note: Note
    #if os(macOS)
        @ScaledMetric private var minimumHeight = 120.0
        @ScaledMetric private var maximumHeight = 320.0
    #else
        @ScaledMetric private var minimumHeight = 112.0
        @ScaledMetric private var maximumHeight = 280.0
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                Text(note.displayTitle).font(.headline).lineLimit(2).layoutPriority(1)
                Spacer(minLength: 0)
            }
            Text(note.text.isEmpty ? "暂无正文" : String(note.text.prefix(600)))
                .font(.subheadline).foregroundStyle(.secondary).lineLimit(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(note.updatedAt, format: .dateTime.month().day())
                .font(.caption).foregroundStyle(.secondary).layoutPriority(1)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: minimumHeight, maxHeight: maximumHeight, alignment: .top)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16).strokeBorder(.primary.opacity(0.1), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct NoteEditorView: View {
    let note: Note
    @Bindable var store: NoteStore
    let saveError: String?
    let retrySave: () -> Void
    @FocusState private var isTitleFocused: Bool
    @FocusState private var isFocused: Bool
    @State private var selection = AttributedTextSelection()
    @State private var showsMarkdownHelp = false
    @State private var showsLinkEditor = false
    @State private var linkAddress = ""
    @State private var showsExport = false
    @State private var exportDocument = MarkdownFile(source: "")
    @State private var exportError: String?
    @State private var didCopyMarkdown = false
    @State private var bodyFocusRequest = 0
    @State private var toast = ToastPresenter()
    @Environment(\.undoManager) private var undoManager
    @Environment(\.fontResolutionContext) private var fontContext

    private var richText: AttributedString {
        store.notes.first(where: { $0.id == note.id })?.richText ?? AttributedString()
    }

    private var editorCanvasColor: Color {
        #if os(macOS)
            Color(nsColor: .textBackgroundColor)
        #else
            Color(uiColor: .systemBackground)
        #endif
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField(
                "无标题",
                text: Binding(
                    get: { store.notes.first(where: { $0.id == note.id })?.title ?? "" },
                    set: { value in
                        store.updateTitle(id: note.id, title: value)
                        guard value.contains(where: { $0.isNewline }) else { return }
                        isTitleFocused = false
                        isFocused = true
                        bodyFocusRequest &+= 1
                    }
                ), axis: .vertical
            )
            .font(.system(size: DocumentTypography.titleSize, weight: .semibold))
            .lineSpacing(DocumentTypography.titleLineSpacing)
            .lineLimit(1...4)
            .textFieldStyle(.plain)
            .submitLabel(.next)
            .focused($isTitleFocused)
            .accessibilityLabel("记录标题")
            .accessibilityIdentifier("note-title")
            .onSubmit {
                isTitleFocused = false
                isFocused = true
                bodyFocusRequest &+= 1
            }
            .padding(.leading, DocumentTypography.titleLeadingInset)
            .frame(maxWidth: DocumentTypography.readingWidth)
            .padding(.horizontal, 32)
            .padding(.top, DocumentTypography.titleTopInset)
            .padding(.bottom, DocumentTypography.titleBottomInset)
            .frame(maxWidth: .infinity)

            NativeRichTextEditor(
                text: Binding(
                    get: { richText },
                    set: { store.updateRichText(id: note.id, text: $0) }
                ), selection: $selection, focusWhenEmpty: false, focusRequest: bodyFocusRequest,
                onEditLink: {
                    linkAddress = selection.attributes(in: richText).compactMap { $0.link?.absoluteString }.first ?? ""
                    showsLinkEditor = true
                },
                onToast: { toast.show($0) }
            )
            .font(.body)
            .frame(maxWidth: .infinity)
            .focused($isFocused)
            .accessibilityLabel("记录正文")
        }
        .background(editorCanvasColor)
        .overlay { ToastOverlay(presenter: toast) }
        .onChange(of: note.id) { _, _ in toast.clear() }
        .onDisappear { toast.clear() }
        .navigationTitle(note.displayTitle)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu("格式", systemImage: "textformat") {
                    Button(formatLabel("加粗") { DocumentTypography.emphasis(in: $0, context: fontContext) & 1 != 0 }, systemImage: "bold") {
                        toggleBold()
                    }
                    .keyboardShortcut("b", modifiers: .command)
                    Button(formatLabel("斜体") { DocumentTypography.emphasis(in: $0, context: fontContext) & 2 != 0 }, systemImage: "italic")
                    { toggleItalic() }
                    .keyboardShortcut("i", modifiers: .command)
                    Button(formatLabel("下划线") { $0.underlineStyle != nil }, systemImage: "underline") {
                        format { $0.underlineStyle = $0.underlineStyle == nil ? .single : nil }
                    }
                    .keyboardShortcut("u", modifiers: .command)
                    Button(formatLabel("删除线") { $0.strikethroughStyle != nil }, systemImage: "strikethrough") {
                        format { $0.strikethroughStyle = $0.strikethroughStyle == nil ? .single : nil }
                    }
                    Divider()
                    ForEach(1...6, id: \.self) { level in
                        Button("标题 \(level)") { paragraph("heading:\(level)") }
                    }
                    Button("正文") { paragraph("body") }
                    Button("无序列表") { paragraph("bullet") }
                    Button("有序列表") { paragraph("numbered") }
                    Button("待办列表") { paragraph("task") }
                    Button("引用") { paragraph("quote") }
                    Button("代码块") { paragraph("code") }
                    Button("插入表格", systemImage: "tablecells") { insertTable() }
                    Button("增加列表缩进") { indentList(outdent: false) }
                    Button("减少列表缩进") { indentList(outdent: true) }
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
                        toggleCode()
                    }
                }
                .accessibilityLabel("格式")
                .disabled(isTitleFocused)
                .help("设置文字格式")
                Menu("Markdown", systemImage: "text.badge.checkmark") {
                    Button("复制为 Markdown", systemImage: "doc.on.doc") { copyMarkdown() }
                        .accessibilityIdentifier("copy-markdown")
                    Button("导出 Markdown…", systemImage: "square.and.arrow.up") {
                        exportDocument = MarkdownFile(source: MarkdownFormatting.serialize(richText, context: fontContext))
                        showsExport = true
                    }
                    .accessibilityIdentifier("export-markdown")
                    Divider()
                    Button("将选区 Markdown 排版") { convertMarkdown(wholeDocument: false) }
                        .disabled(!hasSelection)
                    Button("将全文 Markdown 排版") { convertMarkdown(wholeDocument: true) }
                        .disabled(richText.characters.isEmpty)
                    Divider()
                    Button("支持的语法") { showsMarkdownHelp = true }
                }
                .accessibilityLabel("Markdown")
                .help("Markdown 导出、复制与排版")
            }
            ToolbarItem(placement: .automatic) {
                Text("\(TableData.plainText(in: richText).count) 字符")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { formattingBar.disabled(isTitleFocused) }
        .fileExporter(
            isPresented: $showsExport, document: exportDocument, contentType: MarkdownFile.contentType,
            defaultFilename: note.markdownFilename
        ) { result in
            if case .failure(let error) = result { exportError = error.localizedDescription }
        }
        .alert("无法导出 Markdown", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("好") { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
        .onChange(of: richText) { _, _ in didCopyMarkdown = false }
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
                        Text("输入 **加粗**、*斜体*、~~删除线~~、`代码` 的闭合标记后自动转换。")
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
                        Text(
                            "勾选项可点击切换，不关联独立待办。列表支持基本缩进，尚不支持结构化重排和自动重编号。支持常用 Markdown 的导入、导出和复制。下划线和自定义颜色不属于 Markdown；表格支持单行纯文本单元格、行列操作和对齐；代码块支持语言与基础高亮。图片和 HTML 暂不提供可视化编辑。"
                        )
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
            if note.title.isEmpty && richText.characters.isEmpty { isTitleFocused = true }
        }
    }

    private var formattingBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 14) {
                Menu {
                    Button("正文") { paragraph("body") }
                    ForEach(1...6, id: \.self) { level in
                        Button("标题 \(level)") { paragraph("heading:\(level)") }
                    }
                    Divider()
                    Button("引用") { paragraph("quote") }
                    Button("代码块") { paragraph("code") }
                    Button("插入表格", systemImage: "tablecells") { insertTable() }
                } label: {
                    Label("段落", systemImage: "textformat.size")
                }
                .accessibilityIdentifier("paragraph-menu")
                Divider().frame(height: 18)
                Button {
                    toggleBold()
                } label: {
                    Image(systemName: "bold")
                }
                .help("加粗 ⌘B").accessibilityLabel("加粗").accessibilityIdentifier("format-bold")
                Button {
                    toggleItalic()
                } label: {
                    Image(systemName: "italic")
                }
                .help("斜体 ⌘I").accessibilityLabel("斜体")
                Button {
                    toggleCode()
                } label: {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                }
                .help("行内代码").accessibilityLabel("行内代码")
                Divider().frame(height: 18)
                Menu {
                    Button("无序列表") { paragraph("bullet") }
                    Button("有序列表") { paragraph("numbered") }
                    Button("待办列表") { paragraph("task") }
                    Divider()
                    Button("增加缩进") { indentList(outdent: false) }
                    Button("减少缩进") { indentList(outdent: true) }
                } label: {
                    Label("列表", systemImage: "list.bullet")
                }
                .accessibilityIdentifier("list-menu")
                Button {
                    paragraph("task")
                } label: {
                    Image(systemName: "checklist")
                }
                .help("待办列表").accessibilityLabel("待办列表")
                Button {
                    insertTable()
                } label: {
                    Image(systemName: "tablecells")
                }
                .help("插入表格").accessibilityLabel("插入表格").accessibilityIdentifier("insert-table")
                if didCopyMarkdown {
                    Label("已复制 Markdown", systemImage: "checkmark")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .scrollIndicators(.hidden)
        .background(.bar)
    }

    private func insertTable() {
        var updated = richText
        var body = AttributedString("\n")
        body.font = .body
        body[ParagraphStyleAttribute.self] = "body"
        let table = TableData().attributedText
        updated.replaceSelection(&selection, with: body + table + body)
        store.applyRichEdit(id: note.id, text: updated, undoManager: undoManager)
    }

    private func copyMarkdown() {
        let source = MarkdownFormatting.serialize(richText, context: fontContext)
        #if os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(source, forType: .string)
        #else
            UIPasteboard.general.string = source
        #endif
        didCopyMarkdown = true
    }

    private func toggleCode() {
        let remove = selection.attributes(in: richText).allSatisfy { $0[CodeStyleAttribute.self] == "inline" }
        format {
            $0[CodeStyleAttribute.self] = remove ? nil : "inline"
            $0.font = remove ? ParagraphEditing.font(for: $0[ParagraphStyleAttribute.self] ?? "body") : .body.monospaced()
        }
    }

    private func indentList(outdent: Bool) {
        var updated = richText
        ParagraphEditing.indentList(in: &updated, selection: &selection, outdent: outdent)
        store.applyRichEdit(id: note.id, text: updated, undoManager: undoManager)
        isFocused = true
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
            ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "")
        else { return nil }
        return url
    }

    private func paragraph(_ style: String) {
        var updated = richText
        ParagraphEditing.apply(style, to: &updated, selection: &selection, context: fontContext)
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

    private func toggleBold() { toggleEmphasis(1) }
    private func toggleItalic() { toggleEmphasis(2) }

    private func toggleEmphasis(_ flag: Int) {
        let attributes = selection.attributes(in: richText).map { $0 }
        let remove = !attributes.isEmpty && attributes.allSatisfy { DocumentTypography.emphasis(in: $0, context: fontContext) & flag != 0 }
        format { DocumentTypography.setEmphasis(flag, enabled: !remove, in: &$0, context: fontContext) }
    }

    private func convertMarkdown(wholeDocument: Bool) {
        var updated = richText
        if wholeDocument {
            updated = MarkdownFormatting.renderKeepingBlocks(updated)
            selection = AttributedTextSelection(insertionPoint: updated.endIndex)
        } else {
            guard case .ranges(let ranges) = selection.indices(in: updated),
                ranges.ranges.count == 1, let range = ranges.ranges.first
            else { return }
            let source = AttributedString(updated[range])
            updated.replaceSelection(&selection, with: MarkdownFormatting.renderKeepingBlocks(source))
        }
        store.applyRichEdit(id: note.id, text: updated, undoManager: undoManager)
        isFocused = true
    }
}
