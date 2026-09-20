import SwiftUI

enum CodeLanguageAttribute: CodableAttributedStringKey {
    typealias Value = String
    static let name = "weave.codeLanguage"
}

enum CodeBlockEditing {
    static let languages = [
        (id: "", title: "纯文本"), (id: "swift", title: "Swift"),
        (id: "javascript", title: "JavaScript"), (id: "typescript", title: "TypeScript"),
        (id: "python", title: "Python"), (id: "json", title: "JSON"), (id: "shell", title: "Shell"),
    ]

    static func languageTag(from fence: String) -> String {
        let info = fence.drop(while: { $0 == "`" || $0 == "~" }).trimmingCharacters(in: .whitespaces)
        return String(info.prefix(while: { !$0.isWhitespace && $0 != "`" && $0 != "~" }))
    }

    static func blockRange(in text: AttributedString, selection: AttributedTextSelection) -> NSRange? {
        guard let selected = selectedRange(in: text, selection: selection), !text.characters.isEmpty else { return nil }
        let length = String(text.characters).utf16.count
        let probe = min(selected.location, length - 1)
        var blocks: [(id: String, range: NSRange)] = []
        for run in text.runs {
            guard let id = run[CodeStyleAttribute.self], id.hasPrefix("block:") else { continue }
            let range = NSRange(run.range, in: text)
            if let previous = blocks.last, previous.id == id, NSMaxRange(previous.range) == range.location {
                blocks[blocks.count - 1].range.length += range.length
            } else {
                blocks.append((id, range))
            }
        }
        return blocks.first { NSLocationInRange(probe, $0.range) && NSMaxRange(selected) <= NSMaxRange($0.range) }?.range
    }

    static func setLanguage(_ language: String, in text: inout AttributedString, selection: inout AttributedTextSelection) {
        let selected = selectedRange(in: text, selection: selection)
        if let block = blockRange(in: text, selection: selection), let range = Range<AttributedString.Index>(block, in: text) {
            text[range][CodeLanguageAttribute.self] = language
        }
        var attributes = selection.typingAttributes(in: text)
        guard attributes[CodeStyleAttribute.self]?.hasPrefix("block:") == true || blockRange(in: text, selection: selection) != nil else {
            return
        }
        attributes[CodeLanguageAttribute.self] = language
        if let selected, selected.length == 0, let range = Range<AttributedString.Index>(selected, in: text) {
            selection = AttributedTextSelection(insertionPoint: range.lowerBound, typingAttributes: attributes)
        }
    }

    @discardableResult
    static func indent(in text: inout AttributedString, selection: inout AttributedTextSelection, outdent: Bool) -> Bool {
        guard let block = blockRange(in: text, selection: selection),
            let selected = selectedRange(in: text, selection: selection)
        else { return false }
        let source = String(text.characters) as NSString
        let last = selected.length == 0 ? selected.location : NSMaxRange(selected) - 1
        var location = max(block.location, source.lineRange(for: NSRange(location: selected.location, length: 0)).location)
        var edits: [NSRange] = []
        while location <= last && location < NSMaxRange(block) {
            let line = source.lineRange(for: NSRange(location: location, length: 0))
            let prefix = source.substring(with: NSRange(location: location, length: min(NSMaxRange(line), NSMaxRange(block)) - location))
            let remove = prefix.hasPrefix("\t") ? 1 : min(4, prefix.prefix(while: { $0 == " " }).count)
            if !outdent || remove > 0 { edits.append(NSRange(location: location, length: outdent ? remove : 0)) }
            location = NSMaxRange(line)
        }
        // A trailing newline still belongs to this block; the empty last line has
        // no character run of its own until its first indentation is inserted.
        if !outdent, selected.length == 0, selected.location == source.length,
            source.hasSuffix("\n"), NSMaxRange(block) == source.length
        {
            edits.append(NSRange(location: source.length, length: 0))
        }
        var start = selected.location
        var end = NSMaxRange(selected)
        for edit in edits.reversed() {
            guard let range = Range<AttributedString.Index>(edit, in: text) else { continue }
            let attributes =
                text[range.lowerBound..<text.endIndex].runs.first?.attributes ?? text.runs.last?.attributes ?? AttributeContainer()
            text.replaceSubrange(range, with: AttributedString(outdent ? "" : "    ", attributes: attributes))
            func shifted(_ offset: Int) -> Int {
                guard offset >= edit.location else { return offset }
                return max(edit.location, offset - edit.length) + (outdent ? 0 : 4)
            }
            start = shifted(start)
            end = shifted(end)
        }
        if let restored = Range<AttributedString.Index>(NSRange(location: start, length: end - start), in: text) {
            selection =
                restored.isEmpty ? AttributedTextSelection(insertionPoint: restored.lowerBound) : AttributedTextSelection(range: restored)
        }
        return true
    }

    static func newline(in text: AttributedString, selection: AttributedTextSelection) -> String? {
        guard let selected = selectedRange(in: text, selection: selection), selected.length == 0,
            blockRange(in: text, selection: selection) != nil
        else { return nil }
        let source = String(text.characters) as NSString
        let line = source.lineRange(for: selected)
        let before = source.substring(with: NSRange(location: line.location, length: selected.location - line.location))
        return "\n" + before.prefix(while: { $0 == " " || $0 == "\t" })
    }

    private static func selectedRange(in text: AttributedString, selection: AttributedTextSelection) -> NSRange? {
        switch selection.indices(in: text) {
        case .insertionPoint(let index): return NSRange(index..<index, in: text)
        case .ranges(let ranges):
            guard let first = ranges.ranges.first, let last = ranges.ranges.last else { return nil }
            return NSRange(first.lowerBound..<last.upperBound, in: text)
        }
    }

    struct Token: Equatable {
        enum Kind { case keyword, string, comment, number }
        let range: NSRange
        let kind: Kind
    }

    static func tokens(source: String, language: String) -> [Token] {
        let language = language.lowercased()
        let keywords: String
        let comments: String
        switch language {
        case "swift":
            keywords =
                "actor associatedtype async await break case catch class continue default defer deinit do else enum extension fallthrough false fileprivate for func guard if import in init inout internal is let nil nonisolated open operator override private protocol public repeat rethrows return self Self some static struct subscript super switch throw throws true try typealias var weak where while"
            comments = #"//[^\r\n]*|/\*[\s\S]*?(?:\*/|$)"#
        case "javascript", "js", "typescript", "ts":
            keywords =
                "abstract as async await break case catch class const continue debugger declare default delete do else enum export extends false finally for from function if implements import in instanceof interface let new null of private protected public readonly return static super switch this throw true try type typeof undefined var void while with yield"
            comments = #"//[^\r\n]*|/\*[\s\S]*?(?:\*/|$)"#
        case "python", "py":
            keywords =
                "and as assert async await break class continue def del elif else except False finally for from global if import in is lambda None nonlocal not or pass raise return True try while with yield"
            comments = #"#[^\r\n]*"#
        case "json":
            keywords = "true false null"
            comments = #"(?!)"#
        case "shell", "sh", "bash", "zsh":
            keywords =
                "if then else elif fi for while do done case esac in function select until export local readonly return break continue"
            comments = #"#[^\r\n]*"#
        default: return []
        }
        // A single scanner consumes strings/comments before words, so their content cannot acquire keyword colors.
        let strings =
            #"\"\"\"[\s\S]*?(?:\"\"\"|$)|'''[\s\S]*?(?:'''|$)|\"(?:\\[\s\S]|[^\"\\])*(?:\"|$)|'(?:\\[\s\S]|[^'\\])*(?:'|$)|`(?:\\[\s\S]|[^`\\])*(?:`|$)"#
        let pattern =
            "(" + comments + ")|(" + strings + #")|(\b(?:0[xX][0-9a-fA-F]+|\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)\b)|([\p{L}_$][\p{L}\p{N}_$]*)"#
        guard let scanner = try? NSRegularExpression(pattern: pattern) else { return [] }
        let words = Set(keywords.split(separator: " ").map(String.init))
        let text = source as NSString
        return scanner.matches(in: source, range: NSRange(location: 0, length: text.length)).compactMap { match in
            if match.range(at: 1).location != NSNotFound { return Token(range: match.range, kind: .comment) }
            if match.range(at: 2).location != NSNotFound { return Token(range: match.range, kind: .string) }
            if match.range(at: 3).location != NSNotFound { return Token(range: match.range, kind: .number) }
            return words.contains(text.substring(with: match.range)) ? Token(range: match.range, kind: .keyword) : nil
        }
    }
}
