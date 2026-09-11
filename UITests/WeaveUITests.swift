import XCTest

@MainActor
final class WeaveUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["WEAVE_UI_TEST_SESSION"] = UUID().uuidString
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
    }

    override func tearDownWithError() throws {
        if let app {
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.lifetime = .keepAlways
            add(attachment)
            app.terminate()
        }
    }

    private var editor: XCUIElement { app.textViews["note-editor"] }

    private func newNote() {
        let button = app.buttons["new-note"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        button.tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.tap()
    }

    private func expectText(_ text: String) {
        let predicate = NSPredicate(format: "value == %@", text)
        expectation(for: predicate, evaluatedWith: editor)
        waitForExpectations(timeout: 5)
    }

    func testCreateEditAndRestoreAfterRelaunch() {
        newNote()
        editor.typeText("A persistent note\nSecond line")
        expectText("A persistent note\nSecond line")
        app.terminate()
        app.launch()
        #if os(iOS)
        // Compact navigation starts on the list after relaunch.
        if !editor.waitForExistence(timeout: 2) {
            app.staticTexts["A persistent note"].firstMatch.tap()
        }
        #endif
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        expectText("A persistent note\nSecond line")
    }

    func testMarkdownShortcutRemovesMarkersAndContinuesList() {
        newNote()
        // Deliver keystrokes instead of a paste, matching the shortcut contract.
        for character in "Text**bold**" { editor.typeText(String(character)) }
        expectText("Textbold")
        editor.typeText("\n")
        for character in "- " { editor.typeText(String(character)) }
        editor.typeText("First\nSecond")
        expectText("Textbold\n• First\n• Second")
    }

    #if os(macOS)
    func testUndoShortcutRestoresLiteralSyntax() {
        newNote()
        for character in "**bold**" { editor.typeText(String(character)) }
        expectText("bold")
        editor.typeKey("z", modifierFlags: .command)
        expectText("**bold**")
    }
    #endif
}
