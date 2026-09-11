import SwiftUI
import Testing
@testable import Weave

struct MarkdownFormattingTests {
    @Test func formatsCommonSyntaxAndPreservesChineseParagraphs() {
        let result = MarkdownFormatting.render("# 中文标题\n\n**加粗** 与 *斜体*\n- 列表\n> 引用\n1. 第一项\n- [x] 完成")
        #expect(String(result.characters) == "中文标题\n\n加粗 与 斜体\n• 列表\n│ 引用\n1. 第一项\n☑ 完成")
        let title = result.range(of: "中文标题")!
        #expect(result[title].font == .title)
        let bold = result.range(of: "加粗")!
        #expect(result[bold].font == Font.body.bold())
        let italic = result.range(of: "斜体")!
        #expect(result[italic].font == Font.body.italic())
    }

    @Test func preservesCodeLiterallyAndLinkDestination() {
        let result = MarkdownFormatting.render("```\n**literal**\n```\n[Apple](https://apple.com)")
        #expect(String(result.characters) == "**literal**\nApple")
        #expect(result[result.range(of: "**literal**")!].font == Font.body.monospaced())
        #expect(result[result.range(of: "Apple")!].link == URL(string: "https://apple.com"))
    }

    @Test func unfinishedFenceAndEscapedSyntaxRemainReadable() {
        #expect(String(MarkdownFormatting.render("```\n草稿").characters) == "```\n草稿")
        #expect(String(MarkdownFormatting.render("\\*普通文字\\*").characters) == "*普通文字*")
        #expect(String(MarkdownFormatting.render("").characters).isEmpty)
    }
}
