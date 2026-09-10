import Foundation
import Observation
import SwiftUI

struct Note: Identifiable, Codable, Equatable {
    var id: UUID
    var richText: AttributedString
    var text: String {
        get { String(richText.characters) }
        set { richText = AttributedString(newValue) }
    }
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID, text: String, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.richText = AttributedString(text)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, text, richText, createdAt, updatedAt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        let plainText = try container.decode(String.self, forKey: .text)
        if container.contains(.richText) {
            // An invalid rich document must never silently fall back to plain text.
            richText = try container.decode(AttributedString.self, forKey: .richText,
                                            configuration: NoteAttributeScope.self)
            guard String(richText.characters) == plainText else {
                throw DecodingError.dataCorruptedError(forKey: .richText, in: container,
                                                       debugDescription: "Rich text does not match the plain-text projection.")
            }
        } else {
            richText = AttributedString(plainText)
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(text, forKey: .text)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(richText, forKey: .richText,
                             configuration: NoteAttributeScope.self)
    }

    var title: String {
        nonemptyLines.first ?? "未命名记录"
    }

    var preview: String {
        String(nonemptyLines.dropFirst().joined(separator: " ").prefix(120))
    }

    private var nonemptyLines: [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
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
    private var notesURL: URL { directory.appendingPathComponent("notes.json") }

    init(directory: URL? = nil) {
        self.directory = directory ?? URL.applicationSupportDirectory.appendingPathComponent("Weave", isDirectory: true)
        reload()
    }

    func createNote() {
        guard loadError == nil else { return }
        let now = Date()
        let note = Note(id: UUID(), text: "", createdAt: now, updatedAt: now)
        notes.insert(note, at: 0)
        selectedID = note.id
        hasUnsavedChanges = true
        retrySave()
    }

    func updateText(id: UUID, text: String) {
        updateRichText(id: id, text: AttributedString(text))
    }

    func updateRichText(id: UUID, text: AttributedString) {
        guard loadError == nil,
              let index = notes.firstIndex(where: { $0.id == id }),
              notes[index].richText != text else { return }
        notes[index].richText = text
        notes[index].updatedAt = Date()
        hasUnsavedChanges = true
        retrySave()
    }

    func applyRichEdit(id: UUID, text: AttributedString, undoManager: UndoManager?) {
        guard loadError == nil,
              let previous = notes.first(where: { $0.id == id })?.richText,
              previous != text else { return }
        undoManager?.registerUndo(withTarget: self) { [weak undoManager] store in
            MainActor.assumeIsolated {
                store.applyRichEdit(id: id, text: previous, undoManager: undoManager)
            }
        }
        updateRichText(id: id, text: text)
    }

    func retrySave() {
        guard loadError == nil, hasUnsavedChanges else { return }
        do {
            let encodedNotes = try JSONEncoder().encode(notes)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try encodedNotes.write(to: notesURL, options: .atomic)
            hasUnsavedChanges = false
            saveError = nil
        } catch {
            saveError = "无法保存记录。内容仍保留在当前窗口，请重试。\n\(error.localizedDescription)"
        }
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
