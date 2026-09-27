#if os(macOS)
    import AppKit
    import SwiftUI

    @MainActor @Observable
    final class MacWorkspaceNavigation {
        enum Destination {
            case home, documents, tasks, settings
        }

        var editorID: UUID?
        var destination = Destination.home

        func select(_ destination: Destination) {
            editorID = nil
            self.destination = destination
        }

        func createNote(in store: NoteStore) {
            store.createNote()
            editorID = store.selectedID
            destination = .documents
        }
    }

    extension FocusedValues {
        @Entry var workspaceNavigation: MacWorkspaceNavigation?
    }

    struct MacWorkspaceView: View {
        @Bindable var store: NoteStore
        @Environment(\.colorSchemeContrast) private var contrast
        @Environment(\.colorScheme) private var colorScheme
        @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
        @State private var navigation = MacWorkspaceNavigation()
        @State private var galleryScroll = RecordGalleryScrollState()

        private var notes: [Note] {
            store.notes.sorted { $0.updatedAt > $1.updatedAt }
        }

        var body: some View {
            HStack(spacing: 0) {
                functionRail
                workspaceCard
                    .padding(.trailing, 4)
                    .padding(.bottom, 4)
                    .padding(.top, 6)
            }
            .background {
                if reduceTransparency {
                    Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
                } else {
                    WorkspaceBackdrop().ignoresSafeArea().allowsHitTesting(false)
                }
            }
            .containerBackground(.clear, for: .window)
            .frame(minWidth: 780, minHeight: 460)
            .containerShape(.rect(cornerRadius: 16))
            .focusedSceneValue(\.workspaceNavigation, navigation)
            .onChange(of: navigation.editorID) { _, id in
                if id != nil { navigation.destination = .documents }
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

        private var functionRail: some View {
            VStack(spacing: 6) {
                destinationButton("首页", symbol: "house", isSelected: navigation.destination == .home) {
                    navigation.select(.home)
                }
                .accessibilityIdentifier("workspace-notes")
                destinationButton("文档", symbol: "doc.text", isSelected: navigation.destination == .documents) {
                    navigation.destination = .documents
                    if navigation.editorID == nil {
                        navigation.editorID = notes.first(where: { $0.id == store.selectedID })?.id ?? notes.first?.id
                    }
                }
                .accessibilityIdentifier("workspace-documents")
                destinationButton("任务", symbol: "checkmark.square", isSelected: navigation.destination == .tasks) {
                    navigation.select(.tasks)
                }
                .accessibilityIdentifier("workspace-tasks")
                .help("任务 · 稍后推出")
                Spacer(minLength: 0)
                destinationButton("设置", symbol: "gearshape", isSelected: navigation.destination == .settings) {
                    navigation.select(.settings)
                }
                .accessibilityIdentifier("workspace-settings")
                .help("设置 · 稍后推出")
            }
            .padding(.top, 14)
            .padding(.bottom, 12)
            .frame(width: 48)
            .frame(maxHeight: .infinity)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("功能导航")
        }

        private func destinationButton(
            _ title: String, symbol: String, isSelected: Bool, action: @escaping () -> Void
        ) -> some View {
            Button(action: action) {
                Image(systemName: isSelected ? "\(symbol).fill" : symbol)
                    .accessibilityHidden(true)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .frame(width: 32, height: 32)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 9)
                                .fill(Color.primary.opacity(contrast == .increased ? 0.16 : 0.07))
                        }
                    }
                    .contentShape(.rect(cornerRadius: 9))
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            .help(title)
            .accessibilityLabel(title)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }

        private var workspaceCard: some View {
            HSplitView {
                sidebar
                    .frame(minWidth: 200, idealWidth: 240, maxWidth: 300)
                    .background(WorkspaceSplitPosition())
                VStack(spacing: 0) {
                    detail
                }
                .frame(minWidth: 440, maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
            }
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(workspaceCardShape)
            .background {
                workspaceCardShape
                    .fill(Color(nsColor: .textBackgroundColor))
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.24 : 0.10), radius: 4, y: 1)
                    .allowsHitTesting(false)
            }
            .overlay {
                workspaceCardShape
                    .stroke(Color.primary.opacity(contrast == .increased ? 0.3 : 0.08), lineWidth: 1)
                    .clipShape(workspaceCardShape)
                    .allowsHitTesting(false)
            }
        }

        private var workspaceCardShape: ConcentricRectangle {
            ConcentricRectangle(
                topLeadingCorner: .fixed(16), topTrailingCorner: .fixed(16),
                bottomLeadingCorner: .fixed(16), bottomTrailingCorner: .concentric)
        }

        private var sidebar: some View {
            VStack(spacing: 0) {
                List(selection: $navigation.editorID) {
                    if navigation.destination == .home || navigation.destination == .documents {
                        ForEach(notes) { note in
                            Text(note.displayTitle)
                                .lineLimit(1)
                                .tag(note.id)
                                .accessibilityIdentifier("sidebar-note-\(note.id)")
                                .contentShape(Rectangle())
                                .pointerStyle(.link)
                        }
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                if navigation.destination == .home || navigation.destination == .documents {
                    Button("新建记录", systemImage: "square.and.pencil") {
                        navigation.createNote(in: store)
                    }
                    .accessibilityIdentifier("new-note")
                    .help("新建记录 ⌘N")
                    .buttonStyle(.borderless)
                    .disabled(store.loadError != nil)
                    .pointerStyle(store.loadError == nil ? .link : .default)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
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
            } else if navigation.destination == .tasks {
                ContentUnavailableView("任务稍后推出", systemImage: "checklist", description: Text("独立任务和任务分类正在规划中。你仍可以在记录中使用待办列表。"))
                    .navigationTitle("任务")
            } else if navigation.destination == .settings {
                ContentUnavailableView("设置稍后推出", systemImage: "gearshape", description: Text("个性化设置将在后续加入。"))
                    .navigationTitle("设置")
            } else if let note = store.notes.first(where: { $0.id == navigation.editorID }) {
                NoteEditorView(note: note, store: store, saveError: store.saveError, retrySave: store.retrySave)
                    .id(note.id)
            } else {
                library
            }
        }

        private var library: some View {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("记录").font(.largeTitle.bold())
                    Spacer()
                    Text("\(notes.count) 条记录").foregroundStyle(.secondary)
                }
                .padding(.horizontal, 36).padding(.top, 24).padding(.bottom, 4)
                RecordGallery(notes: notes, scrollState: galleryScroll) { note in
                    Button {
                        navigation.editorID = note.id
                    } label: {
                        RecordCard(note: note)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("note-row-\(note.id)")
                    .accessibilityLabel(note.displayTitle)
                    .accessibilityValue(note.preview)
                    .pointerStyle(.link)
                }
                .overlay {
                    if notes.isEmpty {
                        ContentUnavailableView {
                            Label("从一条记录开始", systemImage: "note.text")
                        } description: {
                            Text("写下想法。")
                        } actions: {
                            Button("新建记录", systemImage: "plus") { navigation.createNote(in: store) }
                                .buttonStyle(.glassProminent)
                                .accessibilityIdentifier("empty-new-note")
                                .pointerStyle(.link)
                        }
                    }
                }
            }
            .navigationTitle("记录")
        }
    }

    /// Sample behind the window while keeping the document surface opaque.
    private struct WorkspaceBackdrop: NSViewRepresentable {
        func makeNSView(context: Context) -> NSVisualEffectView {
            let view = NSVisualEffectView()
            view.material = .underWindowBackground
            view.blendingMode = .behindWindow
            view.state = .followsWindowActiveState
            return view
        }

        func updateNSView(_ view: NSVisualEffectView, context: Context) {}
    }

    /// Set the initial divider once; subsequent resizing remains owned by the native split view.
    private struct WorkspaceSplitPosition: NSViewRepresentable {
        func makeNSView(context: Context) -> InitialPositionView { InitialPositionView() }

        func updateNSView(_ view: InitialPositionView, context: Context) {}

        final class InitialPositionView: NSView {
            private var didSetPosition = false
            private var initialLayoutTask: Task<Void, Never>?

            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                initialLayoutTask?.cancel()
                guard window != nil else { return }
                // SwiftUI must finish mounting and sizing the native split before applying its initial position.
                initialLayoutTask = Task { @MainActor [weak self] in
                    guard !Task.isCancelled else { return }
                    self?.setInitialPosition()
                }
            }

            private func setInitialPosition() {
                guard !didSetPosition, window != nil else { return }
                var ancestor = superview
                while let view = ancestor {
                    if let split = view as? NSSplitView, split.isVertical, split.arrangedSubviews.count == 2, split.bounds.width > 0 {
                        split.layoutSubtreeIfNeeded()
                        didSetPosition = true
                        split.setPosition(240, ofDividerAt: 0)
                        return
                    }
                    ancestor = view.superview
                }
            }

            override func hitTest(_ point: NSPoint) -> NSView? { nil }
        }
    }
#endif
