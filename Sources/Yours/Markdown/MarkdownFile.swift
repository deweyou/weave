import SwiftUI
import UniformTypeIdentifiers

struct MarkdownFile: FileDocument {
    static let contentType = UTType(filenameExtension: "md", conformingTo: .plainText) ?? .plainText
    static var readableContentTypes: [UTType] { [contentType, .plainText] }
    var source: String

    init(source: String) { self.source = source }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
            let source = String(data: data, encoding: .utf8)
        else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        self.source = source
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(source.utf8))
    }
}
