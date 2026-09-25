import Foundation

/// Immutable facts captured before an input rule is evaluated.
struct EditorInputContext {
    let source: NSString
    let range: NSRange
    let replacement: String
    let selection: NSRange
    let paragraph: NSRange
    let line: String
    let trailingBoundary: Int?
    let role: String?
    let codeStyle: String?
    let listMarker: String?
    let isQuoted: Bool

    init(
        storage: NSAttributedString,
        typingAttributes: [NSAttributedString.Key: Any],
        range: NSRange,
        replacement: String,
        selection: NSRange
    ) {
        source = storage.string as NSString
        self.range = range
        self.replacement = replacement
        self.selection = selection

        // A caret after a trailing newline represents TextKit's synthetic empty
        // paragraph, although NSString assigns it to the preceding paragraph.
        let isTerminalEmptyParagraph =
            replacement == "\n" && range.length == 0
            && source.length > 0 && source.hasSuffix("\n")
            && range.location >= source.length - 1
        let paragraphAnchor = isTerminalEmptyParagraph ? source.length : min(range.location, source.length)
        if paragraphAnchor == source.length, source.length > 0,
            source.substring(with: NSRange(location: source.length - 1, length: 1)) == "\n"
        {
            paragraph = NSRange(location: source.length, length: 0)
        } else {
            paragraph = source.paragraphRange(for: NSRange(location: paragraphAnchor, length: 0))
        }
        line = source.substring(with: paragraph).trimmingCharacters(in: .newlines)
        trailingBoundary =
            paragraph.length == 0 && paragraph.location > 0
                && source.substring(with: NSRange(location: paragraph.location - 1, length: 1)) == "\n"
            ? paragraph.location - 1
            : nil

        // UIKit can resolve typing attributes from the following empty paragraph
        // before asking its delegate about Return. Prefer the persisted newline.
        let persistedAnchor = paragraph.location < storage.length ? paragraph.location : trailingBoundary
        role =
            persistedAnchor.flatMap {
                storage.attribute(.weaveParagraphStyle, at: $0, effectiveRange: nil) as? String
            } ?? typingAttributes[.weaveParagraphStyle] as? String
        listMarker =
            typingAttributes[.weaveListMarker] as? String
            ?? persistedAnchor.flatMap { storage.attribute(.weaveListMarker, at: $0, effectiveRange: nil) as? String }
        codeStyle =
            persistedAnchor.flatMap {
                storage.attribute(.weaveCodeStyle, at: $0, effectiveRange: nil) as? String
            } ?? typingAttributes[.weaveCodeStyle] as? String
        let quoteAnchor = range.length > 0 && range.location < storage.length ? range.location : paragraph.location
        isQuoted =
            (trailingBoundary.map {
                storage.attribute(.weaveQuote, at: $0, effectiveRange: nil) as? Bool == true
            } ?? (typingAttributes[.weaveQuote] as? Bool == true))
            || role == "quote"
            || (quoteAnchor < storage.length
                && storage.attribute(.weaveQuote, at: quoteAnchor, effectiveRange: nil) as? Bool == true)
    }
}

enum EditorInputOrigin: Equatable {
    case feature
    case markdownShortcut
}

enum EditorInputCommand: Equatable {
    case applyLink(URL)
    case preserveEmptyQuote
    case indentCode(outdent: Bool)
    case continueCodeLine(String)
    case edit(MarkdownShortcut.Edit, origin: EditorInputOrigin)
    case consume
}

protocol EditorInputFeature: Sendable {
    var id: String { get }
    /// Lower values run first when multiple features can handle the same input.
    var priority: Int { get }
    func command(for context: EditorInputContext) -> EditorInputCommand?
}

/// Evaluates editor features in an explicit precedence order. Features only
/// decide what an input means; the native coordinator owns every mutation.
struct EditorFeatureRegistry {
    let features: [any EditorInputFeature]

    init(features: [any EditorInputFeature] = Self.standardFeatures) {
        precondition(Set(features.map(\.id)).count == features.count, "Editor feature identifiers must be unique")
        self.features = features.enumerated().sorted {
            ($0.element.priority, $0.offset) < ($1.element.priority, $1.offset)
        }.map(\.element)
    }

    func command(for context: EditorInputContext) -> EditorInputCommand? {
        for feature in features {
            if let command = feature.command(for: context) { return command }
        }
        return nil
    }

}
