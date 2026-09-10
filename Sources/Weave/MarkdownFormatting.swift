import SwiftUI

/// A deliberately small Markdown import surface, not a document round-trip codec.
enum MarkdownFormatting {
    static func render(_ source: String) -> AttributedString {
        var result = AttributedString()
        var codeFence: String?
        var codeID = ""
        let lines = source.components(separatedBy: "\n")
        for (index, original) in lines.enumerated() {
            let fence = original.hasPrefix("```") ? "```" : original.hasPrefix("~~~") ? "~~~" : nil
            if let fence, codeFence == nil {
                // Only consume paired fences; incomplete syntax stays editable text.
                if lines.dropFirst(index + 1).contains(where: { $0.trimmingCharacters(in: .whitespaces) == fence }) {
                    codeFence = fence
                    codeID = "block:" + UUID().uuidString
                    continue
                }
            } else if codeFence != nil, original.trimmingCharacters(in: .whitespaces) == codeFence {
                codeFence = nil
                continue
            }

            var line: AttributedString
            var paragraphStyle = "body"
            if codeFence != nil {
                line = AttributedString(original)
                line.font = .body.monospaced()
                line[CodeStyleAttribute.self] = codeID
            } else {
                var content = original
                var font = Font.body
                var prefix = ""
                let hashes = content.prefix(while: { $0 == "#" }).count
                if (1...6).contains(hashes), content.dropFirst(hashes).hasPrefix(" ") {
                    paragraphStyle = "heading:\(hashes)"
                    content = String(content.dropFirst(hashes + 1))
                    font = hashes == 1 ? .title : hashes == 2 ? .title2 : .headline
                } else if content.hasPrefix("> ") {
                    content = String(content.dropFirst(2))
                    prefix = "│ "
                    paragraphStyle = "quote"
                } else if content.hasPrefix("- [ ] ") || content.hasPrefix("- [x] ") || content.hasPrefix("- [X] ") {
                    prefix = content.hasPrefix("- [ ] ") ? "☐ " : "☑ "
                    content = String(content.dropFirst(6))
                } else if ["- ", "* ", "+ "].contains(where: content.hasPrefix) {
                    prefix = "• "
                    content = String(content.dropFirst(2))
                }
                line = inline(content, baseFont: font)
                if !prefix.isEmpty {
                    var marker = AttributedString(prefix)
                    marker.font = .body
                    line = marker + line
                }
            }
            line[ParagraphStyleAttribute.self] = paragraphStyle
            result += line
            if index < lines.count - 1 {
                var newline = AttributedString("\n")
                newline[ParagraphStyleAttribute.self] = paragraphStyle
                if codeFence != nil {
                    newline.font = .body.monospaced()
                    newline[CodeStyleAttribute.self] = codeID
                }
                result += newline
            }
        }
        return result
    }

    private static func inline(_ source: String, baseFont: Font) -> AttributedString {
        var text = (try? AttributedString(markdown: source, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(source)
        for run in text.runs {
            let intent = run.inlinePresentationIntent ?? []
            var font = baseFont
            if intent.contains(.stronglyEmphasized) { font = font.bold() }
            if intent.contains(.emphasized) { font = font.italic() }
            if intent.contains(.code) {
                font = .body.monospaced()
                text[run.range][CodeStyleAttribute.self] = "inline"
            }
            text[run.range].font = font
            if intent.contains(.strikethrough) { text[run.range].strikethroughStyle = .single }
        }
        return text
    }
}
