import Foundation
import JavaScriptCore

/// Owns the JavaScript VM off the UI actor. Only bundled parsers execute, never the user's source.
actor CodeFormatting {
    static let shared = CodeFormatting()
    private var context: JSContext?

    enum Failure: LocalizedError {
        case unsupported, unavailable, tooLarge, changed
        case syntax(String)

        var errorDescription: String? {
            switch self {
            case .unsupported: "此语言暂不支持格式化。"
            case .unavailable: "无法加载代码格式化组件。"
            case .tooLarge: "代码超过 200,000 字符，暂不支持格式化。"
            case .changed: "代码或语言已修改，请重新格式化。"
            case .syntax(let message): "无法格式化，原文已保留。\n" + message
            }
        }
    }

    nonisolated static func parser(for language: String) -> String? {
        switch CodeBlockEditing.canonicalLanguage(language) {
        case "javascript", "jsx": "babel"
        case "typescript", "tsx": "typescript"
        case "json": "json"
        case "html": "html"
        case "css": "css"
        case "scss": "scss"
        case "less": "less"
        case "yaml": "yaml"
        case "markdown": "markdown"
        case "graphql": "graphql"
        default: nil
        }
    }

    func format(_ source: String, language: String) throws -> String {
        try Task.checkCancellation()
        guard let parser = Self.parser(for: language) else { throw Failure.unsupported }
        guard source.utf16.count <= 200_000 else { throw Failure.tooLarge }
        let context = try loadedContext()
        context.exception = nil
        context.setObject(source, forKeyedSubscript: "weaveSource" as NSString)
        context.setObject(parser, forKeyedSubscript: "weaveParser" as NSString)
        // All plugins are bundled and synchronous internally. JavaScriptCore drains
        // their Promise microtasks before evaluateScript returns; tests cover every parser.
        context.evaluateScript(
            """
            globalThis.weaveResult = null;
            prettier.format(weaveSource, {
                parser: weaveParser, plugins: prettierPlugins,
                tabWidth: 2, useTabs: false, endOfLine: "lf",
                embeddedLanguageFormatting: "off"
            }).then(value => { weaveResult = { value }; },
                    error => { weaveResult = { error: String(error.message || error) }; });
            """)
        defer {
            context.setObject(NSNull(), forKeyedSubscript: "weaveSource" as NSString)
            context.setObject(NSNull(), forKeyedSubscript: "weaveResult" as NSString)
        }
        try Task.checkCancellation()
        guard context.exception == nil,
            let result = context.objectForKeyedSubscript("weaveResult"), !result.isNull
        else { throw Failure.unavailable }
        if let error = result.forProperty("error"), !error.isUndefined {
            throw Failure.syntax(error.toString() ?? "请检查代码语法。")
        }
        guard var output = result.forProperty("value")?.toString() else { throw Failure.unavailable }
        // A block's last LF may be the boundary before body text. Preserve that
        // exact boundary instead of adding a paragraph every time formatting runs.
        if output.hasSuffix("\n") { output.removeLast() }
        if source.hasSuffix("\n") { output += "\n" }
        return output
    }

    private func loadedContext() throws -> JSContext {
        if let context { return context }
        guard let candidate = JSContext() else { throw Failure.unavailable }
        #if SWIFT_PACKAGE
            let bundle = Bundle.module
        #else
            let bundle = Bundle.main
        #endif
        for name in ["standalone", "babel", "estree", "typescript", "postcss", "html", "markdown", "yaml", "graphql"] {
            guard let url = bundle.url(forResource: name, withExtension: "js", subdirectory: "CodeFormatting") else {
                throw Failure.unavailable
            }
            candidate.evaluateScript(try String(contentsOf: url, encoding: .utf8))
            guard candidate.exception == nil else { throw Failure.unavailable }
        }
        context = candidate
        return candidate
    }
}
