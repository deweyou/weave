import Testing

@testable import Weave

@MainActor
struct ToastTests {
    @Test func replacementAndRepeatedErrorsCannotBeDismissedByAnOldTimer() {
        let presenter = ToastPresenter()
        let first = ToastMessage(title: "复制失败", message: "请重试。")
        let repeated = ToastMessage(title: "复制失败", message: "请重试。")
        presenter.show(first)
        presenter.show(repeated)
        presenter.dismiss(id: first.id)
        #expect(presenter.message == repeated)
        let different = ToastMessage(title: "格式化失败", message: "原文已保留。", details: "Syntax error")
        presenter.show(different)
        presenter.dismiss(id: repeated.id)
        #expect(presenter.message == different)
        presenter.dismiss(id: different.id)
        #expect(presenter.message == nil)
        presenter.show(first)
        presenter.clear()
        #expect(presenter.message == nil)
    }

    @Test func presentersDoNotLeakBetweenWindows() {
        let first = ToastPresenter()
        let second = ToastPresenter()
        first.show(ToastMessage(title: "复制失败", message: "请重试。"))
        #expect(second.message == nil)
        second.clear()
        #expect(first.message != nil)
    }

    @Test func copyAndFormattingErrorsShareFeedbackWhileSuccessStaysQuiet() {
        let model = CodeHeaderModel()
        var messages: [ToastMessage] = []
        model.onToast = { messages.append($0) }
        model.literal = "example"
        model.writeClipboard = { _ in false }
        model.copyCode()
        #expect(messages.count == 1)
        #expect(messages.first?.title == "复制失败")
        #expect(model.copyStatus == .failed)
        model.writeClipboard = { _ in true }
        model.copyCode()
        #expect(messages.count == 1)
        #expect(model.copyStatus == .copied)
        model.reportFormatFailure(CodeFormatting.Failure.syntax("Unexpected token (2:3)"))
        #expect(messages.count == 2)
        #expect(messages.last?.title == "格式化失败")
        #expect(messages.last?.details?.contains("Unexpected token (2:3)") == true)
        #expect(messages.last?.message.contains("原文已保留") == true)
    }
}
