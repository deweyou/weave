import SwiftUI

/// Private clipboard representation; pasted document objects always receive fresh identities.
enum RichTextClipboard {
    enum ClipboardError: Error, Equatable {
        case unsupportedVersion(Int)
        case invalidTableRange
    }

    private struct Payload: Codable {
        let richText: AttributedString
        private enum CodingKeys: String, CodingKey { case version, richText }

        init(richText: AttributedString) { self.richText = richText }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let version = try container.decode(Int.self, forKey: .version)
            guard version == 1 else { throw ClipboardError.unsupportedVersion(version) }
            richText = try container.decode(AttributedString.self, forKey: .richText, configuration: NoteAttributeScope.self)
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(1, forKey: .version)
            try container.encode(richText, forKey: .richText, configuration: NoteAttributeScope.self)
        }
    }

    static func encode(_ text: AttributedString) throws -> Data {
        try validateTables(in: text)
        return try JSONEncoder().encode(Payload(richText: text))
    }

    static func decode(_ data: Data) throws -> AttributedString {
        let original = try JSONDecoder().decode(Payload.self, from: data).richText
        try validateTables(in: original)
        var pasted = original
        var codeIDs: [String: String] = [:]
        for run in original.runs {
            if var table = run[TableAttribute.self] {
                table.id = UUID()
                pasted[run.range][TableAttribute.self] = table
            }
            if let id = run[CodeStyleAttribute.self], id.hasPrefix("block:") {
                let replacement = codeIDs[id] ?? "block:" + UUID().uuidString
                codeIDs[id] = replacement
                pasted[run.range][CodeStyleAttribute.self] = replacement
            }
        }
        return pasted
    }

    private static func validateTables(in text: AttributedString) throws {
        for run in text.runs where run[TableAttribute.self] != nil {
            guard String(text[run.range].characters) == "\u{FFFC}" else {
                throw ClipboardError.invalidTableRange
            }
        }
    }
}
