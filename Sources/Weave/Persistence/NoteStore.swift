import Foundation
import Observation
import SwiftUI

private actor NotePersistenceWriter {
    private let directory: URL

    init(directory: URL) {
        self.directory = directory
    }

    func write(_ notes: [Note]) throws {
        let encodedNotes = try JSONEncoder().encode(notes)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try encodedNotes.write(to: directory.appendingPathComponent("notes.json"), options: .atomic)
    }
}

@MainActor
@Observable
final class NoteStore {
    private(set) var notes: [Note] = []
    var selectedID: UUID?
    private(set) var loadError: String?
    private(set) var saveError: String?
    private(set) var hasUnsavedChanges = false

    private let directory: URL
    private let writer: NotePersistenceWriter
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var saveRevision = 0
    private var notesURL: URL { directory.appendingPathComponent("notes.json") }

    init(directory: URL? = nil) {
        let directory = directory ?? URL.applicationSupportDirectory.appendingPathComponent("Weave", isDirectory: true)
        self.directory = directory
        writer = NotePersistenceWriter(directory: directory)
        reload()
    }

    func createNote(title: String = "", richText: AttributedString = AttributedString()) {
        guard loadError == nil else { return }
        let now = Date()
        var note = Note(id: UUID(), text: "", createdAt: now, updatedAt: now, title: title)
        note.richText = richText
        notes.insert(note, at: 0)
        selectedID = note.id
        hasUnsavedChanges = true
        scheduleSave()
    }

    func updateTitle(id: UUID, title: String) {
        let normalizedTitle = title.trimmingCharacters(in: .newlines)
            .components(separatedBy: .newlines)
            .joined(separator: " ")
        guard loadError == nil,
            let index = notes.firstIndex(where: { $0.id == id }),
            notes[index].title != normalizedTitle
        else { return }
        notes[index].title = normalizedTitle
        notes[index].updatedAt = Date()
        hasUnsavedChanges = true
        scheduleSave()
    }

    func updateText(id: UUID, text: String) {
        updateRichText(id: id, text: AttributedString(text))
    }

    func updateRichText(id: UUID, text: AttributedString) {
        guard loadError == nil,
            let index = notes.firstIndex(where: { $0.id == id }),
            notes[index].richText != text
        else { return }
        notes[index].richText = text
        notes[index].updatedAt = Date()
        hasUnsavedChanges = true
        scheduleSave()
    }

    func applyRichEdit(id: UUID, text: AttributedString, undoManager: UndoManager?) {
        guard loadError == nil,
            let previous = notes.first(where: { $0.id == id })?.richText,
            previous != text
        else { return }
        undoManager?.registerUndo(withTarget: self) { [weak undoManager] store in
            // UndoManager invokes this target callback synchronously on the
            // main thread where the MainActor-isolated store was registered.
            MainActor.assumeIsolated {
                store.applyRichEdit(id: id, text: previous, undoManager: undoManager)
            }
        }
        updateRichText(id: id, text: text)
    }

    func retrySave() {
        scheduleSave()
    }

    private func scheduleSave() {
        guard loadError == nil, hasUnsavedChanges else { return }
        saveRevision &+= 1
        let revision = saveRevision
        let snapshot = notes
        saveTask?.cancel()
        saveTask = Task { [weak self, writer] in
            do {
                try Task.checkCancellation()
                try await writer.write(snapshot)
                try Task.checkCancellation()
                guard let self, self.saveRevision == revision else { return }
                self.hasUnsavedChanges = false
                self.saveError = nil
            } catch is CancellationError {
                // A newer snapshot owns the pending save.
            } catch {
                guard let self, self.saveRevision == revision else { return }
                self.saveError = "无法保存记录。内容仍保留在当前窗口，请重试。\n\(error.localizedDescription)"
            }
        }
    }

    func flushPendingSave() async {
        await saveTask?.value
    }

    func reload() {
        // Failed writes must not be replaced by an older on-disk snapshot.
        guard !hasUnsavedChanges else { return }
        do {
            let decodedNotes: [Note]
            do {
                let encodedNotes = try Data(contentsOf: notesURL)
                decodedNotes = try JSONDecoder().decode([Note].self, from: encodedNotes)
            } catch CocoaError.fileReadNoSuchFile {
                decodedNotes = []
            }
            guard Set(decodedNotes.map(\.id)).count == decodedNotes.count else {
                loadError = "记录文件包含重复标识，已暂停编辑以保护原始内容。请恢复文件后重新读取。"
                return
            }
            notes = decodedNotes
            if !notes.contains(where: { $0.id == selectedID }) {
                selectedID = notes.first?.id
            }
            loadError = nil
            saveError = nil
        } catch {
            loadError = "无法读取记录，已暂停编辑以保护原始内容。请恢复文件后重新读取。\n\(error.localizedDescription)"
        }
    }
}
