import SwiftUI

enum CodeLanguageAttribute: CodableAttributedStringKey {
    typealias Value = String
    static let name = "weave.codeLanguage"
}

enum CodeBlockEditing {
    static let indentationWidth = 2
    static let indentation = String(repeating: " ", count: indentationWidth)
    static let languages = [
        (id: "", title: "plain text"), (id: "swift", title: "Swift"),
        (id: "javascript", title: "JavaScript"), (id: "typescript", title: "TypeScript"),
        (id: "jsx", title: "JSX"), (id: "tsx", title: "TSX"),
        (id: "python", title: "Python"), (id: "json", title: "JSON"), (id: "shell", title: "Shell"),
        (id: "html", title: "HTML"), (id: "xml", title: "XML"),
        (id: "css", title: "CSS"), (id: "scss", title: "SCSS"), (id: "less", title: "Less"),
        (id: "sql", title: "SQL"), (id: "yaml", title: "YAML"), (id: "markdown", title: "Markdown"),
        (id: "graphql", title: "GraphQL"), (id: "go", title: "Go"), (id: "rust", title: "Rust"),
        (id: "java", title: "Java"), (id: "kotlin", title: "Kotlin"),
        (id: "c", title: "C"), (id: "cpp", title: "C++"), (id: "csharp", title: "C#"),
        (id: "ruby", title: "Ruby"), (id: "php", title: "PHP"),
    ]

    static func canonicalLanguage(_ language: String) -> String {
        switch language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "js", "javascript": "javascript"
        case "ts", "typescript": "typescript"
        case "py", "python": "python"
        case "sh", "bash", "zsh", "shell": "shell"
        case "yml", "yaml": "yaml"
        case "md", "markdown": "markdown"
        case "htm", "html": "html"
        case "c++", "cc", "cxx", "hpp", "cpp": "cpp"
        case "cs", "c#", "csharp": "csharp"
        case "rs", "rust": "rust"
        case "kt", "kts", "kotlin": "kotlin"
        case "rb", "ruby": "ruby"
        case "golang", "go": "go"
        case "gql", "graphql": "graphql"
        default: language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
    }

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
            let remove = prefix.hasPrefix("\t") ? 1 : min(indentationWidth, prefix.prefix(while: { $0 == " " }).count)
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
            text.replaceSubrange(range, with: AttributedString(outdent ? "" : indentation, attributes: attributes))
            func shifted(_ offset: Int) -> Int {
                guard offset >= edit.location else { return offset }
                return max(edit.location, offset - edit.length) + (outdent ? 0 : indentationWidth)
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
        let language = canonicalLanguage(language)
        let keywords: String
        let comments: String
        switch language {
        case "swift":
            keywords =
                "actor associatedtype async await break case catch class continue default defer deinit do else enum extension fallthrough false fileprivate for func guard if import in init inout internal is let nil nonisolated open operator override private protocol public repeat rethrows return self Self some static struct subscript super switch throw throws true try typealias var weak where while"
            comments = #"//[^\r\n]*|/\*[\s\S]*?(?:\*/|$)"#
        case "javascript", "typescript", "jsx", "tsx":
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
        case "go":
            keywords =
                "break case chan const continue default defer else fallthrough for func go goto if import interface map package range return select struct switch type var true false nil"
            comments = #"//[^\r\n]*|/\*[\s\S]*?(?:\*/|$)"#
        case "rust":
            keywords =
                "as async await break const continue crate dyn else enum extern false fn for if impl in let loop match mod move mut pub ref return self Self static struct super trait true type unsafe use where while"
            comments = #"//[^\r\n]*|/\*[\s\S]*?(?:\*/|$)"#
        case "java", "kotlin", "c", "cpp", "csharp":
            keywords =
                "abstract alignas alignof as auto bool boolean break byte case catch char class companion const constexpr continue data default delegate delete do double else enum event explicit export extern false final finally float for friend fun goto if implements import in inline int interface internal is lateinit long mutable namespace native new null nullptr object operator out override package params private protected public record ref register return sealed short signed sizeof static string struct super suspend switch synchronized template this throw throws true try typealias typedef typename union unsigned using val var virtual void volatile when while"
            comments = #"//[^\r\n]*|/\*[\s\S]*?(?:\*/|$)"#
        case "ruby":
            keywords =
                "alias and begin break case class def defined do else elsif end ensure false for if in module next nil not or redo rescue retry return self super then true undef unless until when while yield"
            comments = #"#[^\r\n]*|(?m:^=begin\b)[\s\S]*?(?:^=end\b|$)"#
        case "php":
            keywords =
                "abstract and array as break callable case catch class clone const continue declare default die do echo else elseif empty endfor endforeach endif endswitch endwhile eval exit extends false final finally fn for foreach function global goto if implements include include_once instanceof interface isset list match namespace new null or print private protected public readonly require require_once return static switch throw trait true try unset use var while xor yield"
            comments = #"//[^\r\n]*|#[^\r\n]*|/\*[\s\S]*?(?:\*/|$)"#
        case "sql":
            keywords =
                "select from where join inner left right full outer on as and or not null true false insert into values update set delete create alter drop table index view primary foreign key references default unique constraint group by having order asc desc limit offset union all distinct case when then else end exists in is like between count sum avg min max with recursive returning begin commit rollback"
            comments = #"--[^\r\n]*|/\*[\s\S]*?(?:\*/|$)"#
        case "html", "xml":
            keywords = ""
            comments = #"<!--[\s\S]*?(?:-->|$)"#
        case "css", "scss", "less":
            keywords = "important inherit initial unset revert none auto"
            comments = language == "css" ? #"/\*[\s\S]*?(?:\*/|$)"# : #"//[^\r\n]*|/\*[\s\S]*?(?:\*/|$)"#
        case "yaml":
            keywords = "true false null yes no on off"
            comments = #"#[^\r\n]*"#
        case "markdown":
            keywords = ""
            comments = #"<!--[\s\S]*?(?:-->|$)"#
        case "graphql":
            keywords =
                "query mutation subscription fragment on schema scalar type interface union enum input extend directive implements true false null"
            comments = #"#[^\r\n]*"#
        default: return []
        }
        // A single scanner consumes strings/comments before words, so their content cannot acquire keyword colors.
        let strings =
            #"\"\"\"[\s\S]*?(?:\"\"\"|$)|'''[\s\S]*?(?:'''|$)|\"(?:\\[\s\S]|[^\"\\])*(?:\"|$)|'(?:\\[\s\S]|[^'\\])*(?:'|$)|`(?:\\[\s\S]|[^`\\])*(?:`|$)"#
        let special: String
        switch language {
        case "html", "xml", "jsx", "tsx": special = #"</?[A-Za-z][\w:.-]*|<!DOCTYPE\b"#
        case "css", "scss", "less": special = #"[.#@$]?[A-Za-z_-][\w-]*(?=\s*[:{])|#[0-9a-fA-F]{3,8}\b"#
        case "yaml": special = #"[\p{L}_][\p{L}\p{N}_-]*(?=\s*:)"#
        case "markdown": special = #"(?m:^#{1,6} .+$)|\*\*[^\r\n]*?\*\*|!?(?:\[[^\]\r\n]*\])\([^\)\r\n]*\)"#
        default: special = #"(?!)"#
        }
        let pattern =
            "(" + comments + ")|(" + strings + #")|(\b(?:0[xX][0-9a-fA-F]+|\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)\b)|("#
            + special + #")|([\p{L}_$][\p{L}\p{N}_$]*)"#
        guard let scanner = try? NSRegularExpression(pattern: pattern) else { return [] }
        let words = Set(keywords.split(separator: " ").map(String.init))
        let text = source as NSString
        return scanner.matches(in: source, range: NSRange(location: 0, length: text.length)).compactMap { match in
            if match.range(at: 1).location != NSNotFound { return Token(range: match.range, kind: .comment) }
            if match.range(at: 2).location != NSNotFound { return Token(range: match.range, kind: .string) }
            if match.range(at: 3).location != NSNotFound { return Token(range: match.range, kind: .number) }
            if match.range(at: 4).location != NSNotFound { return Token(range: match.range, kind: .keyword) }
            let word = text.substring(with: match.range)
            return words.contains(language == "sql" || language == "yaml" ? word.lowercased() : word)
                ? Token(range: match.range, kind: .keyword) : nil
        }
    }
}
