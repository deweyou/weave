import SwiftUI

@main
struct WeaveApp: App {
    @State private var store: NoteStore
    @Environment(\.scenePhase) private var scenePhase

    #if os(macOS)
        @FocusedValue(\.workspaceNavigation) private var navigation
    #endif

    init() {
        #if DEBUG
            // A UUID names an isolated test store; never accept an arbitrary data path.
            if let value = ProcessInfo.processInfo.environment["WEAVE_UI_TEST_SESSION"],
                let session = UUID(uuidString: value)
            {
                let directory = URL.applicationSupportDirectory
                    .appendingPathComponent("WeaveUITests", isDirectory: true)
                    .appendingPathComponent(session.uuidString, isDirectory: true)
                if let count = ProcessInfo.processInfo.environment["WEAVE_UI_TEST_GALLERY_COUNT"].flatMap(Int.init),
                    [1_000, 10_000].contains(count),
                    !FileManager.default.fileExists(atPath: directory.appendingPathComponent("notes.json").path)
                {
                    // Fixtures are allowed only inside the UUID-isolated Debug store.
                    let notes = (0..<count).map { index in
                        let date = Date(timeIntervalSince1970: 1_700_000_000 - Double(index))
                        return Note(
                            id: UUID(), text: String(repeating: "中文笔记与 mixed text 👋。\n", count: index % 12 + 1),
                            createdAt: date, updatedAt: date, title: String(format: "Gallery %04d", index))
                    }
                    do {
                        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                        try JSONEncoder().encode(notes).write(to: directory.appendingPathComponent("notes.json"), options: .atomic)
                    } catch {
                        preconditionFailure("Cannot prepare isolated gallery fixture: \(error)")
                    }
                }
                _store = State(initialValue: NoteStore(directory: directory))
                return
            }
        #endif
        _store = State(initialValue: NoteStore())
    }

    var body: some Scene {
        WindowGroup {
            WorkspaceView(store: store)
                .tint(AppTheme.accent)
                .onChange(of: scenePhase) { _, phase in
                    guard phase != .active else { return }
                    Task { await store.flushPendingSave() }
                }
        }
        #if os(macOS)
            .defaultSize(width: 1000, height: 720)
            .commands {
                CommandGroup(replacing: .newItem) {
                    Button("新建记录", systemImage: "square.and.pencil") {
                        navigation?.createNote(in: store)
                    }
                    .keyboardShortcut("n", modifiers: .command)
                    .disabled(store.loadError != nil || navigation == nil)
                }
            }
        #endif
    }
}
