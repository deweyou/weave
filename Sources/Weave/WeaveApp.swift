import SwiftUI

@main
struct WeaveApp: App {
    @State private var store = NoteStore()

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
