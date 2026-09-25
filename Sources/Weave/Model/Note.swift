import Foundation
import SwiftUI

struct NoteFolder: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var name: String
}

struct Note: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var title: String
    var folderID: UUID?
    var richText: AttributedString
    var text: String {
        get { TableData.plainText(in: richText) }
        set { richText = AttributedString(newValue) }
    }
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID, text: String, createdAt: Date, updatedAt: Date, title: String = "", folderID: UUID? = nil) {
        self.id = id
        self.title = title
        self.folderID = folderID
        self.richText = AttributedString(text)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, titleSeparated, text, richText, createdAt, updatedAt, folderID
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        folderID = try container.decodeIfPresent(UUID.self, forKey: .folderID)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        let plainText = try container.decode(String.self, forKey: .text)
        let storedTitle = try container.decodeIfPresent(String.self, forKey: .title)
        let titleSeparated = try container.decodeIfPresent(Bool.self, forKey: .titleSeparated) ?? false
        if container.contains(.richText) {
            // An invalid rich document must never silently fall back to plain text.
            richText = try container.decode(
                AttributedString.self, forKey: .richText,
                configuration: NoteAttributeScope.self)
            guard TableData.plainText(in: richText) == plainText else {
                throw DecodingError.dataCorruptedError(
                    forKey: .richText, in: container,
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
        try container.encodeIfPresent(folderID, forKey: .folderID)
        try container.encode(title, forKey: .title)
        try container.encode(true, forKey: .titleSeparated)
        try container.encode(text, forKey: .text)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(
            richText, forKey: .richText,
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
