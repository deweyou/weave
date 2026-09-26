#if os(macOS)
    import AppKit
    import SwiftUI
    import UniformTypeIdentifiers

    enum NoteLocation: Hashable {
        case recent, all, unfiled
        case folder(UUID)
    }

    private enum WorkspaceDestination: Hashable {
        case notes, tasks
        case location(NoteLocation)
        case note(UUID)
    }

    @MainActor @Observable
    final class MacWorkspaceNavigation {
        var location: NoteLocation = .all
        var editorID: UUID?
        var showsTasks = false
        var query = ""

        func browse(_ location: NoteLocation) {
            self.location = location
            editorID = nil
            showsTasks = false
            query = ""
        }

        func createNote(in store: NoteStore) {
            let folderID: UUID?
            if case .folder(let id) = location, !showsTasks { folderID = id } else { folderID = nil }
            store.createNote(folderID: folderID)
            editorID = store.selectedID
            showsTasks = false
            query = ""
        }
    }

    extension FocusedValues {
        @Entry var workspaceNavigation: MacWorkspaceNavigation?
    }

    struct MacWorkspaceView: View {
        @Bindable var store: NoteStore
        @State private var navigation = MacWorkspaceNavigation()
        @State private var expandedFolders: Set<UUID> = []
        @State private var showsImport = false
        @State private var importError: String?
        @State private var showsFolderEditor = false
        @State private var editingFolderID: UUID?
        @State private var folderName = ""
        @State private var galleryOffset: CGFloat = 0

        private var title: String {
            switch navigation.location {
            case .recent: "最近"
            case .all: "记录"
            case .unfiled: "未分类"
            case .folder(let id): store.folders.first(where: { $0.id == id })?.name ?? "分类"
            }
        }

        private var notes: [Note] {
            let filtered = store.notes.filter { note in
                let matches: Bool
                switch navigation.location {
                case .recent, .all: matches = true
                case .unfiled: matches = note.folderID == nil
                case .folder(let id): matches = note.folderID == id
                }
                return matches
                    && (navigation.query.isEmpty || note.title.localizedStandardContains(navigation.query)
                        || note.text.localizedStandardContains(navigation.query))
            }
            return filtered.sorted { $0.updatedAt > $1.updatedAt }
        }

        var body: some View {
            NavigationSplitView {
                sidebar
                    .navigationTitle("Weave")
                    .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 320)
            } detail: {
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .textBackgroundColor))
                    .toolbar {
                        if !navigation.showsTasks {
                            ToolbarItem(placement: .primaryAction) {
                                Button("新建记录", systemImage: "square.and.pencil") { navigation.createNote(in: store) }
                                    .accessibilityIdentifier("new-note")
                                    .help("新建记录 ⌘N")
                                    .disabled(store.loadError != nil)
                            }
                        }
                    }
            }
            .frame(minWidth: 720, minHeight: 460)
            .focusedSceneValue(\.workspaceNavigation, navigation)
            .onChange(of: navigation.location) { _, _ in galleryOffset = 0 }
            .onChange(of: navigation.query) { _, _ in galleryOffset = 0 }
            .fileImporter(isPresented: $showsImport, allowedContentTypes: [MarkdownFile.contentType, .plainText]) { result in
                do {
                    let url = try result.get()
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let source = try String(contentsOf: url, encoding: .utf8)
                    let folderID: UUID?
                    if case .folder(let id) = navigation.location { folderID = id } else { folderID = nil }
                    store.createNote(
                        title: url.deletingPathExtension().lastPathComponent,
                        richText: MarkdownFormatting.render(source), folderID: folderID
                    )
                    navigation.editorID = store.selectedID
                    navigation.query = ""
                } catch { importError = error.localizedDescription }
            }
            .alert("无法导入 Markdown", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
                Button("好") { importError = nil }
            } message: {
                Text(importError ?? "")
            }
            .alert(editingFolderID == nil ? "新建分类" : "重命名分类", isPresented: $showsFolderEditor) {
                TextField("分类名称", text: $folderName)
                    .accessibilityIdentifier("folder-name")
                Button("取消", role: .cancel) {}
                Button("保存") { saveFolder() }
                    .disabled(folderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if navigation.editorID == nil, let error = store.saveError {
                    HStack {
                        Label("尚未保存：\(error)", systemImage: "exclamationmark.triangle")
                        Spacer()
                        Button("重试") { store.retrySave() }
                    }.padding().background(.bar)
                }
            }
        }

        private var sidebar: some View {
            List(
                selection: Binding<WorkspaceDestination?>(
                    get: {
                        if navigation.showsTasks { return .tasks }
                        if let id = navigation.editorID { return .note(id) }
                        return .location(navigation.location)
                    },
                    set: { destination in
                        switch destination {
                        case .notes: navigation.browse(.all)
                        case .tasks:
                            navigation.showsTasks = true
                            navigation.editorID = nil
                        case .location(let location): navigation.browse(location)
                        case .note(let id): navigation.editorID = id
                        case nil: break
                        }
                    }
                )
            ) {
                Section {
                    Label("记录", systemImage: "note.text")
                        .fontWeight(navigation.showsTasks ? .regular : .semibold)
                        .tag(WorkspaceDestination.notes)
                        .accessibilityIdentifier("workspace-notes")
                    HStack {
                        Label("任务", systemImage: "checklist")
                        Spacer()
                        Text("稍后推出").font(.caption).foregroundStyle(.secondary)
                    }
                    .tag(WorkspaceDestination.tasks)
                    .accessibilityIdentifier("workspace-tasks")
                }
                if !navigation.showsTasks {
                    Section("记录") {
                        locationRow("最近", symbol: "clock", location: .recent)
                        locationRow("全部记录", symbol: "tray.full", location: .all)
                        locationRow("未分类", symbol: "tray", location: .unfiled)
                    }
                    Section {
                        ForEach(store.folders) { folder in
                            DisclosureGroup(
                                isExpanded: Binding(
                                    get: { expandedFolders.contains(folder.id) },
                                    set: { if $0 { expandedFolders.insert(folder.id) } else { expandedFolders.remove(folder.id) } }
                                )
                            ) {
                                ForEach(store.notes.filter { $0.folderID == folder.id }) { note in
                                    Label(note.displayTitle, systemImage: "doc.text").lineLimit(1)
                                        .tag(WorkspaceDestination.note(note.id))
                                        .contextMenu { noteActions(note) }
                                }
                            } label: {
                                locationRow(folder.name, symbol: "folder", location: .folder(folder.id))
                                    .accessibilityIdentifier("folder-row-\(folder.id)")
                                    .contextMenu {
                                        Button("重命名…") {
                                            editingFolderID = folder.id
                                            folderName = folder.name
                                            showsFolderEditor = true
                                        }
                                    }
                            }
                            .tag(WorkspaceDestination.location(.folder(folder.id)))
                        }
                    } header: {
                        Text("分类")
                    }
                }
            }
            .listStyle(.sidebar)
            .buttonStyle(.borderless)
            .safeAreaInset(edge: .bottom) {
                if !navigation.showsTasks {
                    VStack(alignment: .leading, spacing: 14) {
                        Button("新建分类", systemImage: "folder.badge.plus") {
                            editingFolderID = nil
                            folderName = ""
                            showsFolderEditor = true
                        }
                        .accessibilityIdentifier("new-folder")
                        Button("导入 Markdown…", systemImage: "square.and.arrow.down") { showsImport = true }
                            .accessibilityIdentifier("import-markdown")
                    }
                    .buttonStyle(.borderless)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .disabled(store.loadError != nil)
                }
            }
        }

        private func locationRow(_ label: String, symbol: String, location: NoteLocation) -> some View {
            Label(label, systemImage: symbol)
                .lineLimit(1)
                .tag(WorkspaceDestination.location(location))
                .contentShape(Rectangle())
                // List does not write its selection again when the selected row is clicked.
                .simultaneousGesture(TapGesture().onEnded { navigation.browse(location) })
        }

        @ViewBuilder private var detail: some View {
            if let error = store.loadError {
                ContentUnavailableView {
                    Label("无法读取记录", systemImage: "exclamationmark.triangle")
                } description: {
                    Text("原文件已保留。\n\(error)")
                } actions: {
                    Button("重新读取") { store.reload() }
                }
            } else if navigation.showsTasks {
                ContentUnavailableView("任务稍后推出", systemImage: "checklist", description: Text("独立任务和任务分类正在规划中。你仍可以在记录中使用待办列表。"))
                    .navigationTitle("任务")
            } else if let note = store.notes.first(where: { $0.id == navigation.editorID }) {
                NoteEditorView(note: note, store: store, saveError: store.saveError, retrySave: store.retrySave)
                    .id(note.id)
                    .toolbar {
                        ToolbarItem(placement: .navigation) {
                            Button("返回\(title)", systemImage: "chevron.left") { navigation.editorID = nil }
                                .accessibilityIdentifier("back-to-notes")
                                .keyboardShortcut("[", modifiers: .command)
                        }
                        ToolbarItem(placement: .primaryAction) {
                            Menu("整理记录", systemImage: "ellipsis.circle") { noteActions(note) }
                                .accessibilityIdentifier("organize-note")
                        }
                    }
            } else {
                library
            }
        }

        private var library: some View {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(.largeTitle.bold())
                    Spacer()
                    Text("\(notes.count) 条记录").foregroundStyle(.secondary)
                }
                .padding(.horizontal, 32).padding(.top, 24).padding(.bottom, 20)
                RecordGallery(notes: notes, scrollOffset: $galleryOffset) { note in
                    Button {
                        navigation.editorID = note.id
                    } label: {
                        RecordCard(note: note)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("note-row-\(note.id)")
                    .contextMenu { noteActions(note) }
                }
                .overlay {
                    if notes.isEmpty {
                        if !navigation.query.isEmpty {
                            ContentUnavailableView.search(text: navigation.query)
                        } else {
                            ContentUnavailableView {
                                Label("从一条记录开始", systemImage: "note.text")
                            } description: {
                                Text("写下想法，把内容慢慢整理起来。")
                            } actions: {
                                Button("新建记录", systemImage: "plus") { navigation.createNote(in: store) }
                                    .buttonStyle(.glassProminent)
                                    .accessibilityIdentifier("empty-new-note")
                            }
                        }
                    }
                }
            }
            .navigationTitle(title)
            .searchable(text: $navigation.query, prompt: "搜索\(title)")
        }

        @ViewBuilder private func noteActions(_ note: Note) -> some View {
            Menu("移动到分类", systemImage: "folder") {
                Button("未分类") { store.moveNote(id: note.id, to: nil) }
                ForEach(store.folders) { folder in
                    Button(folder.name) { store.moveNote(id: note.id, to: folder.id) }
                }
            }
        }

        private func saveFolder() {
            if let editingFolderID {
                store.renameFolder(id: editingFolderID, name: folderName)
            } else if let id = store.createFolder(name: folderName) {
                navigation.browse(.folder(id))
            }
        }
    }
#endif
