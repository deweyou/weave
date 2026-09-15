import Foundation
import Observation
import SwiftUI

struct Note: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var richText: AttributedString
    var text: String {
        get { TableData.plainText(in: richText) }
        set { richText = AttributedString(newValue) }
    }
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID, text: String, createdAt: Date, updatedAt: Date, title: String = "") {
        self.id = id
        self.title = title
        self.richText = AttributedString(text)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, titleSeparated, text, richText, createdAt, updatedAt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        let plainText = try container.decode(String.self, forKey: .text)
        let storedTitle = try container.decodeIfPresent(String.self, forKey: .title)
        let titleSeparated = try container.decodeIfPresent(Bool.self, forKey: .titleSeparated) ?? false
        if container.contains(.richText) {
            // An invalid rich document must never silently fall back to plain text.
            richText = try container.decode(AttributedString.self, forKey: .richText,
                                            configuration: NoteAttributeScope.self)
            guard TableData.plainText(in: richText) == plainText else {
                throw DecodingError.dataCorruptedError(forKey: .richText, in: container,
                                                       debugDescription: "Rich text does not match the plain-text projection.")
            }
        } else {
            richText = AttributedString(plainText)
        }
        ParagraphEditing.migrateLegacyAttributes(&richText)
        if titleSeparated {
            title = storedTitle ?? ""
        } else {
            let migrated = Self.migrateLegacyTitle(from: richText)
            if let storedTitle {
                title = storedTitle
                if !storedTitle.isEmpty, storedTitle.trimmingCharacters(in: .whitespacesAndNewlines) == migrated.title {
                    richText = migrated.body
                }
            } else {
                (title, richText) = migrated
            }
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(true, forKey: .titleSeparated)
        try container.encode(text, forKey: .text)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(richText, forKey: .richText,
                             configuration: NoteAttributeScope.self)
    }

    var displayTitle: String {
        let collapsed = title.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return collapsed.isEmpty ? "未命名记录" : collapsed
    }

    var markdownFilename: String {
        String(displayTitle.prefix(80)).components(separatedBy: CharacterSet(charactersIn: "/:\n\r")).joined(separator: "-")
    }

    var preview: String {
        String(nonemptyLines.joined(separator: " ").prefix(120))
    }

    private var nonemptyLines: [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private static func migrateLegacyTitle(from richText: AttributedString) -> (title: String, body: AttributedString) {
        let characters = richText.characters
        var lineStart = characters.startIndex
        while lineStart < characters.endIndex {
            let lineEnd = characters[lineStart...].firstIndex(where: { $0.isNewline }) ?? characters.endIndex
            let title = String(characters[lineStart..<lineEnd]).trimmingCharacters(in: .whitespaces)
            if !title.isEmpty {
                let bodyStart = lineEnd < characters.endIndex ? characters.index(after: lineEnd) : lineEnd
                return (title, AttributedString(richText[bodyStart...]))
            }
            guard lineEnd < characters.endIndex else { break }
            lineStart = characters.index(after: lineEnd)
        }
        return ("", AttributedString())
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

    func createNote(title: String = "", richText: AttributedString = AttributedString()) {
        guard loadError == nil else { return }
        let now = Date()
        var note = Note(id: UUID(), text: "", createdAt: now, updatedAt: now, title: title)
        note.richText = richText
        notes.insert(note, at: 0)
        selectedID = note.id
        hasUnsavedChanges = true
        retrySave()
    }

    func updateTitle(id: UUID, title: String) {
        let normalizedTitle = title.components(separatedBy: .newlines).joined(separator: " ")
        guard loadError == nil,
              let index = notes.firstIndex(where: { $0.id == id }),
              notes[index].title != normalizedTitle else { return }
        notes[index].title = normalizedTitle
        notes[index].updatedAt = Date()
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
