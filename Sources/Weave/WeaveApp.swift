import SwiftUI

@main
struct WeaveApp: App {
    @State private var store: NoteStore

    init() {
        #if DEBUG
        // A UUID names an isolated test store; never accept an arbitrary data path.
        if let value = ProcessInfo.processInfo.environment["WEAVE_UI_TEST_SESSION"],
           let session = UUID(uuidString: value) {
            let directory = URL.applicationSupportDirectory
                .appendingPathComponent("WeaveUITests", isDirectory: true)
                .appendingPathComponent(session.uuidString, isDirectory: true)
            _store = State(initialValue: NoteStore(directory: directory))
            return
        }
        #endif
        _store = State(initialValue: NoteStore())
    }

    var body: some Scene {
        WindowGroup {
            WorkspaceView(store: store)
        }
        #if os(macOS)
        .defaultSize(width: 1000, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新建记录", systemImage: "square.and.pencil") {
                    store.createNote()
                }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(store.loadError != nil)
            }
        }
        #endif
    }
}
