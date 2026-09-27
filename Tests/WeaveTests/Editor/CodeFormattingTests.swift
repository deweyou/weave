import Foundation
import Testing

@testable import Weave

struct CodeFormattingTests {
    @Test(arguments: [
        ("javascript", "const value={name:'中文🌿',items:[1,2]};"),
        ("typescript", "const value:{name:string}={name:'中文🌿'}"),
        ("jsx", "const view=<div name='中文🌿'><span>hello</span></div>"),
        ("tsx", "const view:JSX.Element=<div name='中文🌿'/>"),
        ("json", "{\"name\":\"中文🌿\",\"items\":[1,2]}"),
        ("html", "<div  class=\"item\"><span>中文🌿</span><span>hello</span></div>"),
        ("css", ".item{color:red;margin:0  2px}/*中文🌿*/"),
        ("scss", "$color:red;.item{color:$color;&:hover{color:blue}}/*中文🌿*/"),
        ("less", "@color:red;.item{color:@color;}/*中文🌿*/"),
        ("yaml", "name: 中文🌿\nitems: [1,2]"),
        ("markdown", "# 标题\n\n-   中文🌿\n-   hello"),
        ("graphql", "query Example{user(id:1){name email}} # 中文🌿"),
    ])
    func formatsEveryAdvertisedLanguageAndIsIdempotent(language: String, source: String) async throws {
        let output = try await CodeFormatting.shared.format(source, language: language)
        #expect(output.contains("中文🌿"))
        #expect(output != source)
        #expect(!output.hasSuffix("\n"))
        #expect(try await CodeFormatting.shared.format(output, language: language) == output)
        #expect(try await CodeFormatting.shared.format(source + "\n", language: language) == output + "\n")
    }

    @Test func usesTwoSpacesAndDoesNotExecuteSource() async throws {
        let source = "function example(){\nthrow new Error('Do not execute');\n}"
        let output = try await CodeFormatting.shared.format(source, language: "js")
        #expect(output == "function example() {\n  throw new Error(\"Do not execute\");\n}")
        let json = try await CodeFormatting.shared.format("{\"id\":9007199254740993,\"id\":2}", language: "json")
        #expect(json.contains("9007199254740993"))
        #expect(json.components(separatedBy: "\"id\"").count == 3)
    }

    @Test(arguments: ["javascript", "json", "typescript", "graphql"])
    func rejectsInvalidCode(language: String) async {
        await #expect(throws: CodeFormatting.Failure.self) {
            try await CodeFormatting.shared.format("{ invalid :", language: language)
        }
    }

    @Test func rejectsUnsupportedAndOversizedCode() async {
        #expect(CodeFormatting.parser(for: "swift") == nil)
        #expect(CodeFormatting.parser(for: "") == nil)
        #expect(CodeFormatting.parser(for: "YML") == "yaml")
        await #expect(throws: CodeFormatting.Failure.self) {
            try await CodeFormatting.shared.format("print(1)", language: "python")
        }
        await #expect(throws: CodeFormatting.Failure.self) {
            try await CodeFormatting.shared.format(String(repeating: " ", count: 200_001), language: "json")
        }
    }
}
