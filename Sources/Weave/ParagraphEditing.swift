import SwiftUI

enum ParagraphStyleAttribute: CodableAttributedStringKey {
    typealias Value = String
    static let name = "weave.paragraphStyle"
}

enum ParagraphEditing {
    static func paragraphRange(in text: AttributedString, selection: AttributedTextSelection) -> Range<AttributedString.Index>? {
        let nsRange: NSRange
        switch selection.indices(in: text) {
        case .insertionPoint(let index): nsRange = NSRange(index..<index, in: text)
        case .ranges(let ranges):
            guard let first = ranges.ranges.first, let last = ranges.ranges.last else { return nil }
            nsRange = NSRange(first.lowerBound..<last.upperBound, in: text)
        }
        let source = String(text.characters) as NSString
        guard source.length > 0 else { return nil }
        return Range<AttributedString.Index>(source.paragraphRange(for: nsRange), in: text)
    }

    static func apply(_ style: String, to text: inout AttributedString, selection: inout AttributedTextSelection) {
        guard let range = paragraphRange(in: text, selection: selection) else {
            var attributes = selection.typingAttributes(in: text)
            attributes[ParagraphStyleAttribute.self] = style
            attributes.font = font(for: style)
            attributes[CodeStyleAttribute.self] = style == "code" ? "block:" + UUID().uuidString : nil
            selection = AttributedTextSelection(insertionPoint: text.endIndex, typingAttributes: attributes)
            return
        }
        let originalRange = NSRange(range, in: text)
        var content = AttributedString(text[range])
        let source = String(content.characters) as NSString
        var paragraphs: [NSRange] = []
        var location = 0
        while location < source.length {
            let paragraph = source.paragraphRange(for: NSRange(location: location, length: 0))
            paragraphs.append(paragraph)
            location = NSMaxRange(paragraph)
        }
        for (index, paragraph) in paragraphs.enumerated().reversed() {
            let line = source.substring(with: paragraph)
            let oldPrefix = MarkdownShortcut.listPrefix(line)?.prefix ?? ""
            let marker: String
            switch style {
            case "bullet": marker = "• "
            case "numbered": marker = "\(index + 1). "
            case "task": marker = "☐ "
            default: marker = ""
            }
            if let prefixRange = Range<AttributedString.Index>(NSRange(location: paragraph.location, length: oldPrefix.utf16.count), in: content) {
                content.replaceSubrange(prefixRange, with: AttributedString(marker))
            }
        }
        content[ParagraphStyleAttribute.self] = style
        content[CodeStyleAttribute.self] = style == "code" ? "block:" + UUID().uuidString : nil
        content.font = font(for: style)
        text.replaceSubrange(range, with: content)
        if let selected = Range<AttributedString.Index>(NSRange(location: originalRange.location, length: String(content.characters).utf16.count), in: text) {
            selection = AttributedTextSelection(range: selected)
        }
    }

    static func font(for style: String) -> Font {
        switch style {
        case "heading:1": .title
        case "heading:2": .title2
        case "heading:3", "heading:4", "heading:5", "heading:6": .headline
        case "code": .body.monospaced()
        default: .body
        }
    }

    static func toggleTask(in text: inout AttributedString, selection: inout AttributedTextSelection) {
        guard let range = paragraphRange(in: text, selection: selection) else { return }
        let source = String(text[range].characters)
        let indent = source.prefix(while: { $0 == "\t" })
        let marker = source.dropFirst(indent.count).first
        guard marker == "☐" || marker == "☑" else { return }
        let start = text.characters.index(range.lowerBound, offsetBy: indent.count)
        let end = text.characters.index(after: start)
        var replacement = AttributedString(marker == "☐" ? "☑" : "☐")
        replacement.setAttributes(text[start..<end].runs.first?.attributes ?? AttributeContainer())
        let offset = NSRange(start..<end, in: text).location
        text.replaceSubrange(start..<end, with: replacement)
        if let restored = Range<AttributedString.Index>(NSRange(location: offset, length: 0), in: text) {
            selection = AttributedTextSelection(insertionPoint: restored.lowerBound)
        }
    }
}
