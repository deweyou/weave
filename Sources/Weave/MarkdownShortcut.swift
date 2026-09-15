import Foundation

enum MarkdownShortcut {
    enum Style: Equatable {
        case heading(Int), bullet, quote, bold, italic, strike, code, body, numbered, task, codeBlock
    }

    struct Edit: Equatable {
        let range: NSRange
        let replacement: String
        let style: Style
    }

    static func listPrefix(_ line: String) -> (prefix: String, next: String, style: Style)? {
        let indent = String(line.prefix(while: { $0 == "\t" }))
        let body = String(line.dropFirst(indent.count))
        for (marker, next, style) in [("• ", "• ", Style.bullet), ("│ ", "│ ", Style.quote), ("☐ ", "☐ ", Style.task), ("☑ ", "☐ ", Style.task)] where body.hasPrefix(marker) {
            return (indent + marker, indent + next, style)
        }
        if let range = body.range(of: #"^\d{1,6}\. "#, options: .regularExpression),
           let number = Int(body[range].dropLast(2)), number < 999999 {
            return (indent + String(body[range]), indent + "\(number + 1). ", .numbered)
        }
        return nil
    }

    static func match(text: String, range: NSRange, replacement: String, hasMarkedText: Bool) -> Edit? {
        guard !hasMarkedText, range.length == 0, replacement.count == 1,
              let insertion = Range(range, in: text) else { return nil }
        let before = text[..<insertion.lowerBound]
        let lineStart = before.lastIndex(where: { $0.isNewline }).map { text.index(after: $0) } ?? text.startIndex
        let line = String(text[lineStart..<insertion.lowerBound])
        let lineOffset = text[..<lineStart].utf16.count

        if replacement == "\n", line.hasPrefix("```"), !line.dropFirst(3).contains("`") {
            return Edit(range: NSRange(location: lineOffset, length: line.utf16.count), replacement: "", style: .codeBlock)
        }
        if replacement == " " {
            if ["[]", "[ ]", "- [ ]", "• [ ]"].contains(line) {
                return Edit(range: NSRange(location: lineOffset, length: line.utf16.count), replacement: "", style: .task)
            }
            if line.range(of: #"^\d{1,6}\.$"#, options: .regularExpression) != nil {
                return Edit(range: NSRange(location: lineOffset, length: line.utf16.count), replacement: line + " ", style: .numbered)
            }
            if (1...6).contains(line.count), line.allSatisfy({ $0 == "#" }) {
                return Edit(range: NSRange(location: lineOffset, length: line.utf16.count), replacement: "", style: .heading(line.count))
            }
            if ["-", "*", "+"].contains(line) {
                return Edit(range: NSRange(location: lineOffset, length: 1), replacement: "• ", style: .bullet)
            }
            if line == ">" {
                return Edit(range: NSRange(location: lineOffset, length: 1), replacement: "", style: .quote)
            }
        }

        if replacement == "\n" {
            if let item = listPrefix(line) {
                let content = line.dropFirst(item.prefix.count)
                let atLineEnd = insertion.lowerBound == text.endIndex || text[insertion.lowerBound].isNewline
                if content.allSatisfy({ $0.isWhitespace }), atLineEnd {
                    return Edit(range: NSRange(location: lineOffset, length: line.utf16.count), replacement: "", style: .body)
                }
                return Edit(range: range, replacement: "\n" + item.next, style: item.style)
            }
            return nil
        }

        guard replacement == "*" || replacement == "`" || replacement == "~" else { return nil }
        let candidate = line + replacement
        let patterns: [(String, Style)] = replacement == "*" ? [
            (#"(?<![\\*])\*\*([^*\r\n]+)\*\*$"#, .bold),
            (#"(?<![\\*])\*([^*\r\n]+)\*$"#, .italic)
        ] : replacement == "~" ? [(#"(?<![\\~])~~([^~\r\n]+)~~$"#, .strike)] : [(#"(?<![\\`])`([^`\r\n]+)`$"#, .code)]
        for (pattern, style) in patterns {
            if insertion.lowerBound != text.endIndex {
                let next = text[insertion.lowerBound]
                // Keep a delimiter run intact, but allow text and other inline formats beside it.
                if String(next) == replacement { continue }
            }
            guard let expression = try? NSRegularExpression(pattern: pattern),
                  let match = expression.firstMatch(in: candidate, range: NSRange(location: 0, length: candidate.utf16.count)),
                  let contentRange = Range(match.range(at: 1), in: candidate),
                  let matchRange = Range(match.range, in: candidate) else { continue }
            let content = String(candidate[contentRange])
            guard content.first?.isWhitespace == false, content.last?.isWhitespace == false,
                  !content.hasSuffix("\\") else { continue }
            // Asterisks inside an unfinished inline code span must remain literal.
            let preceding = candidate[..<matchRange.lowerBound]
            // A single star inside an unfinished bold span is not a new italic opener.
            if style == .italic, preceding.range(of: #"(?:^|[^\\*])\*\*[^*]*$"#, options: .regularExpression) != nil { continue }
            var isEscaped = false
            var backticks = 0
            for character in preceding {
                if character == "`", !isEscaped { backticks += 1 }
                isEscaped = character == "\\" && !isEscaped
            }
            guard backticks.isMultiple(of: 2) else { continue }
            return Edit(range: NSRange(location: lineOffset + match.range.location, length: match.range.length - replacement.utf16.count), replacement: content, style: style)
        }
        return nil
    }
}
