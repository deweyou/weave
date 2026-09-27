#if os(iOS)
    import SwiftUI
    import UniformTypeIdentifiers

    private enum MobileLibrary: Hashable {
        case recent, all, unfiled, tasks
        case folder(UUID)
        case document(UUID)

        var folderID: UUID? {
            if case .folder(let id) = self { return id }
            return nil
        }
    }

    struct MobileWorkspaceView: View {
        @Bindable var store: NoteStore
        @State private var library: MobileLibrary?
        @State private var path: [UUID] = []
        @State private var compactColumn: NavigationSplitViewColumn = .sidebar
        @State private var query = ""
        @State private var expandedFolders: Set<UUID> = []
        @State private var showsFolderEditor = false
        @State private var editingFolderID: UUID?
        @State private var folderName = ""
        @State private var galleryOffset: CGFloat = 0
        @State private var movingNote: Note?
        @State private var showsImport = false
        @State private var importFromSidebar = false
        @State private var importError: String?

        private var activeFolderID: UUID? {
            if case .document(let id) = library { return store.notes.first(where: { $0.id == id })?.folderID }
            return library?.folderID
        }

        private var isEditing: Bool {
            if case .document = library { return true }
            return !path.isEmpty
        }

        private var title: String {
            switch library ?? .all {
            case .recent: "最近"
            case .all: "记录"
            case .unfiled: "未分类"
            case .tasks: "任务"
            case .document(let id): store.notes.first(where: { $0.id == id })?.displayTitle ?? "记录"
            case .folder(let id): store.folders.first(where: { $0.id == id })?.name ?? "分类"
            }
        }

        private var notes: [Note] {
            store.notes.filter { note in
                let matches: Bool
                switch library ?? .all {
                case .recent, .all: matches = true
                case .unfiled: matches = note.folderID == nil
                case .folder(let id): matches = note.folderID == id
                case .tasks, .document: matches = false
                }
                return matches
                    && (query.isEmpty || note.title.localizedStandardContains(query) || note.text.localizedStandardContains(query))
            }.sorted { $0.updatedAt > $1.updatedAt }
        }

        var body: some View {
            // Keep one split/stack hierarchy across size changes so an active editor
            // is not replaced when iPad changes between wide and compact layouts.
            NavigationSplitView(preferredCompactColumn: $compactColumn) {
                sidebar
                    .navigationTitle("Weave")
                    .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
            } detail: {
                NavigationStack(path: $path) {
                    libraryContent
                        .navigationTitle(title)
                        .navigationDestination(for: UUID.self) { id in
                            editor(id)
                        }
                }
            }
            .navigationSplitViewStyle(.balanced)
            .onChange(of: query) { _, _ in galleryOffset = 0 }
            .alert(editingFolderID == nil ? "新建分类" : "重命名分类", isPresented: $showsFolderEditor) {
                TextField("分类名称", text: $folderName).accessibilityIdentifier("folder-name")
                Button("取消", role: .cancel) {}
                Button("保存") {
                    if let editingFolderID {
                        store.renameFolder(id: editingFolderID, name: folderName)
                    } else if let id = store.createFolder(name: folderName) {
                        select(.folder(id))
                        compactColumn = .detail
                    }
                }
                .disabled(folderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .sheet(item: $movingNote) { note in
                NavigationStack {
                    List {
                        moveDestination("未分类", folderID: nil, note: note)
                        ForEach(store.folders) { folder in
                            moveDestination(folder.name, folderID: folder.id, note: note)
                        }
                    }
                    .navigationTitle("移动到分类")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("取消") { movingNote = nil } }
                    }
                }
                .presentationDetents([.medium, .large])
            }
            .fileImporter(isPresented: $showsImport, allowedContentTypes: [MarkdownFile.contentType, .plainText]) { result in
                do {
                    let url = try result.get()
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let source = try String(contentsOf: url, encoding: .utf8)
                    prepareNewNote()
                    store.createNote(
                        title: url.deletingPathExtension().lastPathComponent,
                        richText: MarkdownFormatting.render(source), folderID: activeFolderID
                    )
                    openCreatedNote(fromSidebar: importFromSidebar)
                } catch { importError = error.localizedDescription }
            }
            .alert("无法导入 Markdown", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
                Button("好") { importError = nil }
            } message: {
                Text(importError ?? "")
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !isEditing, let error = store.saveError {
                    HStack {
                        Label("尚未保存：\(error)", systemImage: "exclamationmark.triangle")
                        Button("重试") { store.retrySave() }
                    }.font(.callout).padding().background(.bar)
                }
            }
        }

        private var sidebar: some View {
            List(selection: Binding(get: { library }, set: { select($0) })) {
                Section {
                    NavigationLink(value: MobileLibrary.all) { Label("记录", systemImage: "note.text") }
                        .accessibilityIdentifier("workspace-notes")
                    NavigationLink(value: MobileLibrary.tasks) {
                        HStack {
                            Label("任务", systemImage: "checklist")
                            Spacer()
                            Text("稍后推出").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("workspace-tasks")
                }
                if library != .tasks {
                    Section("记录") {
                        libraryLink("最近", symbol: "clock", destination: .recent)
                        libraryLink("全部记录", symbol: "tray.full", destination: .all)
                        libraryLink("未分类", symbol: "tray", destination: .unfiled)
                    }
                    Section("分类") {
                        ForEach(store.folders) { folder in
                            DisclosureGroup(
                                isExpanded: Binding(
                                    get: { expandedFolders.contains(folder.id) },
                                    set: { if $0 { expandedFolders.insert(folder.id) } else { expandedFolders.remove(folder.id) } }
                                )
                            ) {
                                ForEach(store.notes.filter { $0.folderID == folder.id }) { note in
                                    Button {
                                        select(.document(note.id))
                                        compactColumn = .detail
                                    } label: {
                                        Label(note.displayTitle, systemImage: "doc.text").lineLimit(1)
                                    }
                                    .contextMenu { noteActions(note) }
                                }
                            } label: {
                                libraryLink(folder.name, symbol: "folder", destination: .folder(folder.id))
                                    .contextMenu {
                                        Button("重命名…", systemImage: "pencil") { editFolder(folder) }
                                    }
                            }
                        }
                        Button("新建分类", systemImage: "folder.badge.plus") { editFolder(nil) }
                            .accessibilityIdentifier("new-folder")
                            .disabled(store.loadError != nil)
                    }
                }
            }
            .listStyle(.sidebar)
            .toolbar { libraryToolbar(fromSidebar: true) }
        }

        private func libraryLink(_ name: String, symbol: String, destination: MobileLibrary) -> some View {
            NavigationLink(value: destination) { Label(name, systemImage: symbol).lineLimit(1) }
        }

        @ViewBuilder private var libraryContent: some View {
            if let error = store.loadError {
                ContentUnavailableView {
                    Label("无法读取记录", systemImage: "exclamationmark.triangle")
                } description: {
                    Text("原文件已保留。\n\(error)")
                } actions: {
                    Button("重新读取") { store.reload() }
                }
            } else if case .document(let id) = library {
                editor(id)
            } else if library == .tasks {
                ContentUnavailableView("任务稍后推出", systemImage: "checklist", description: Text("独立任务和任务分类正在规划中。你仍可以在记录中使用待办列表。"))
            } else {
                RecordGallery(notes: notes, scrollOffset: $galleryOffset) { note in
                    NavigationLink(value: note.id) {
                        RecordCard(note: note)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("note-row-\(note.id)")
                    .contextMenu { noteActions(note) }
                }
                .searchable(text: $query, prompt: "搜索\(title)")
                .overlay {
                    if notes.isEmpty {
                        if !query.isEmpty {
                            ContentUnavailableView.search(text: query)
                        } else {
                            ContentUnavailableView {
                                Label("从一条记录开始", systemImage: "note.text")
                            } description: {
                                Text("写下想法，把内容慢慢整理起来。")
                            } actions: {
                                Button("新建记录", systemImage: "plus") { createNote() }
                                    .buttonStyle(.glassProminent).accessibilityIdentifier("empty-new-note")
                            }
                        }
                    }
                }
                .toolbar { libraryToolbar(fromSidebar: false) }
            }
        }

        @ToolbarContentBuilder private func libraryToolbar(fromSidebar: Bool) -> some ToolbarContent {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu("记录操作", systemImage: "ellipsis.circle") {
                    Button("新建分类", systemImage: "folder.badge.plus") { editFolder(nil) }
                    if case .folder(let id) = library, let folder = store.folders.first(where: { $0.id == id }) {
                        Button("重命名分类…", systemImage: "pencil") { editFolder(folder) }
                    }
                    Button("导入 Markdown…", systemImage: "square.and.arrow.down") {
                        importFromSidebar = fromSidebar
                        showsImport = true
                    }
                    .accessibilityIdentifier("import-markdown")
                }
                .accessibilityIdentifier("library-actions")
                .disabled(store.loadError != nil)
                Button("新建记录", systemImage: "square.and.pencil") { createNote(fromSidebar: fromSidebar) }
                    .accessibilityIdentifier("new-note")
                    .keyboardShortcut("n", modifiers: .command)
                    .disabled(store.loadError != nil)
            }
        }

        @ViewBuilder private func noteActions(_ note: Note) -> some View {
            Button("移动到分类", systemImage: "folder") { movingNote = note }
        }

        private func moveDestination(_ name: String, folderID: UUID?, note: Note) -> some View {
            Button {
                store.moveNote(id: note.id, to: folderID)
                movingNote = nil
            } label: {
                HStack {
                    Label(name, systemImage: "folder")
                    Spacer()
                    if note.folderID == folderID { Image(systemName: "checkmark").accessibilityLabel("当前分类") }
                }
            }
        }

        private func select(_ destination: MobileLibrary?) {
            guard library != destination else { return }
            galleryOffset = 0
            library = destination
            path = []
            query = ""
        }

        private func editFolder(_ folder: NoteFolder?) {
            editingFolderID = folder?.id
            folderName = folder?.name ?? ""
            showsFolderEditor = true
        }

        private func prepareNewNote() {
            if library == nil || library == .tasks { select(.all) }
            query = ""
        }

        private func createNote(fromSidebar: Bool = false) {
            prepareNewNote()
            store.createNote(folderID: activeFolderID)
            openCreatedNote(fromSidebar: fromSidebar)
        }

        private func openCreatedNote(fromSidebar: Bool) {
            guard let id = store.selectedID else { return }
            if fromSidebar {
                select(.document(id))
            } else {
                path = [id]
            }
            compactColumn = .detail
        }

        @ViewBuilder private func editor(_ id: UUID) -> some View {
            if let note = store.notes.first(where: { $0.id == id }) {
                NoteEditorView(note: note, store: store, saveError: store.saveError, retrySave: store.retrySave)
                    .id(id)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Menu("整理记录", systemImage: "ellipsis.circle") { noteActions(note) }
                                .accessibilityIdentifier("organize-note")
                        }
                    }
            }
        }
    }
#endif
