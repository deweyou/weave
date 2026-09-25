import XCTest

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

@MainActor
final class WeaveUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["WEAVE_UI_TEST_SESSION"] = UUID().uuidString
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        #if os(macOS)
            // Window restoration is process-global for the bundle identifier. A prior
            // run that quit without an open window must not suppress the test window.
            app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        #endif
        app.launch()
        #if os(macOS)
            app.activate()
            if !app.windows.firstMatch.waitForExistence(timeout: 3) {
                // AppKit can finish terminating the previous UI-test instance after
                // the next launch request. Relaunch once when that race leaves only
                // the application menu and no document window.
                app.terminate()
                app.launch()
                app.activate()
            }
            XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
        #endif
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
        #if os(macOS)
            // On small desktops the toolbar action moves into its overflow menu.
            // A fresh store exposes the primary action in the empty detail view.
            let button = app.buttons["empty-new-note"]
        #else
            let button = app.buttons["new-note"]
        #endif
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

    #if os(macOS)
        private func recordCard(titled title: String) -> XCUIElement {
            app.buttons.matching(
                NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "note-row-", title)
            ).firstMatch
        }

        func testMacRecordGalleryAndReturn() {
            newNote()
            app.textFields["note-title"].tap()
            app.textFields["note-title"].typeText("Gallery record\n")
            editor.typeText("A quick thought for the gallery")
            app.buttons["back-to-notes"].tap()
            XCTAssertTrue(app.scrollViews["record-gallery"].waitForExistence(timeout: 5))
            let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "note-row-")).firstMatch
            XCTAssertTrue(card.waitForExistence(timeout: 5))
            card.tap()
            expectText("A quick thought for the gallery")
            app.buttons["back-to-notes"].tap()
            let search = app.searchFields.firstMatch
            search.tap()
            search.typeText("thought")
            XCTAssertTrue(card.exists)
            search.typeText(" missing")
            XCTAssertFalse(card.exists)
            app.staticTexts["workspace-notes"].firstMatch.tap()
            XCTAssertTrue(card.waitForExistence(timeout: 5))
        }

        func testMacLibraryFoldersAndSearch() {
            app.buttons["new-folder"].tap()
            let field = app.textFields["分类名称"]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.typeText("Layout category")
            app.buttons["保存"].tap()
            newNote()
            let title = app.textFields["note-title"]
            title.tap()
            title.typeText("Layout note")
            title.typeText("\n")
            editor.typeText("Content search token")
            app.buttons["back-to-notes"].tap()
            XCTAssertTrue(recordCard(titled: "Layout note").waitForExistence(timeout: 5))
            app.staticTexts["全部记录"].firstMatch.tap()
            XCTAssertTrue(recordCard(titled: "Layout note").waitForExistence(timeout: 5))
            XCTAssertTrue(app.scrollViews["record-gallery"].exists)
            let search = app.searchFields.firstMatch
            XCTAssertTrue(search.waitForExistence(timeout: 5))
            search.tap()
            search.typeText("search token")
            XCTAssertTrue(recordCard(titled: "Layout note").exists)
            search.typeText(" missing")
            XCTAssertFalse(recordCard(titled: "Layout note").exists)
            app.staticTexts["全部记录"].firstMatch.tap()
            recordCard(titled: "Layout note").tap()
            app.menuButtons["organize-note"].tap()
            app.menuItems["移动到分类"].tap()
            app.menuItems["未分类"].tap()
            app.buttons["back-to-notes"].tap()
            app.staticTexts["未分类"].firstMatch.tap()
            XCTAssertTrue(recordCard(titled: "Layout note").waitForExistence(timeout: 5))
            app.terminate()
            app.launch()
            app.staticTexts["全部记录"].firstMatch.tap()
            recordCard(titled: "Layout note").tap()
            expectText("Content search token")
            app.buttons["back-to-notes"].tap()
            app.staticTexts["Layout category"].firstMatch.tap()
            XCTAssertTrue(app.buttons["empty-new-note"].waitForExistence(timeout: 5))
        }

        private func copiedMarkdown() -> String {
            let pasteboard = NSPasteboard.general
            let previousChangeCount = pasteboard.changeCount
            app.menuButtons["Markdown"].tap()
            app.menuItems["copy-markdown"].tap()
            let deadline = Date().addingTimeInterval(3)
            while pasteboard.changeCount == previousChangeCount, Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            }
            XCTAssertNotEqual(pasteboard.changeCount, previousChangeCount, "复制 Markdown 后剪贴板应更新")
            return pasteboard.string(forType: .string) ?? ""
        }
    #endif

    func testCreateEditAndRestoreAfterRelaunch() {
        newNote()
        let title = app.textFields["note-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        let titleText = "Independent title that wraps when the available width becomes narrow"
        title.typeText(titleText)
        title.typeText("\n")
        editor.typeText("A persistent note\nSecond line")
        expectText("A persistent note\nSecond line")
        app.terminate()
        app.launch()
        // Both workspaces reopen on their library after relaunch.
        if !editor.waitForExistence(timeout: 2) {
            #if os(iOS)
                app.buttons["全部记录"].firstMatch.tap()
                app.staticTexts[titleText].firstMatch.tap()
            #else
                recordCard(titled: titleText).tap()
            #endif
        }
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        expectText("A persistent note\nSecond line")
        XCTAssertEqual(app.textFields["note-title"].value as? String, titleText)
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

    func testEmptyNoteCanStartTaskListFromToolbar() {
        newNote()
        let tasks = app.buttons["待办列表"]
        XCTAssertTrue(tasks.waitForExistence(timeout: 5))
        tasks.tap()
        editor.tap()
        editor.typeText("First task")
        expectText("First task")
    }

    #if os(iOS)
        func testIPadEditorSurvivesRotation() throws {
            guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("iPad window scenario") }
            app.buttons["workspace-notes"].firstMatch.tap()
            app.buttons["empty-new-note"].tap()
            XCTAssertTrue(editor.waitForExistence(timeout: 5))
            editor.tap()
            editor.typeText("Keep this editor through rotation")
            XCUIDevice.shared.orientation = .landscapeLeft
            expectText("Keep this editor through rotation")
            XCTAssertTrue(app.buttons["workspace-notes"].isHittable)
            editor.typeText(" continued")
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "iPad wide editor"
            attachment.lifetime = .keepAlways
            add(attachment)
            XCUIDevice.shared.orientation = .portrait
            expectText("Keep this editor through rotation continued")
        }

        func testMobileSearchAndReturn() {
            app.buttons["全部记录"].firstMatch.tap()
            app.buttons["empty-new-note"].tap()
            XCTAssertTrue(editor.waitForExistence(timeout: 5))
            app.textFields["note-title"].tap()
            app.textFields["note-title"].typeText("Searchable note\n")
            editor.tap()
            editor.typeText("Distinctive body token")
            app.navigationBars.buttons.element(boundBy: 0).tap()
            let search = app.searchFields.firstMatch
            XCTAssertTrue(search.waitForExistence(timeout: 5))
            search.tap()
            search.typeText("Distinctive")
            XCTAssertTrue(app.staticTexts["Searchable note"].exists)
            search.typeText("zzz")
            XCTAssertFalse(app.staticTexts["Searchable note"].exists)
            search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 3))
            app.staticTexts["Searchable note"].tap()
            expectText("Distinctive body token")
            app.navigationBars.buttons.element(boundBy: 0).tap()
            let cancelSearch = app.buttons.matching(
                NSPredicate(format: "label IN %@", ["关闭", "Close", "取消", "Cancel"])
            ).firstMatch
            XCTAssertTrue(cancelSearch.waitForExistence(timeout: 5))
            cancelSearch.tap()
            app.navigationBars.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(app.buttons["workspace-tasks"].waitForExistence(timeout: 5))
            app.buttons["workspace-tasks"].tap()
            XCTAssertTrue(app.staticTexts["任务稍后推出"].waitForExistence(timeout: 5))
        }

        func testMobileLibraryOrganizationAndRestoration() {
            app.buttons["new-folder"].tap()
            let name = app.alerts.textFields.firstMatch
            XCTAssertTrue(name.waitForExistence(timeout: 5))
            name.typeText("Mobile folder")
            app.alerts.buttons["保存"].tap()
            app.buttons["empty-new-note"].tap()
            XCTAssertTrue(editor.waitForExistence(timeout: 5))
            let title = app.textFields["note-title"]
            title.tap()
            title.typeText("Mobile note\n")
            editor.tap()
            editor.typeText("Persistent mobile content")
            app.navigationBars.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(app.staticTexts["Mobile note"].waitForExistence(timeout: 5))
            app.staticTexts["Mobile note"].tap()
            app.buttons["organize-note"].tap()
            app.buttons["移动到分类"].tap()
            app.buttons["未分类"].tap()
            app.navigationBars.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(app.buttons["empty-new-note"].waitForExistence(timeout: 5))
            app.terminate()
            app.launch()
            app.buttons["全部记录"].firstMatch.tap()
            app.staticTexts["Mobile note"].tap()
            expectText("Persistent mobile content")
        }
    #endif

    #if os(iOS)
        func testTableTouchEditingAndReturnToDocument() {
            newNote()
            app.buttons["insert-table"].tap()
            let header = app.textFields["table-cell-0-0"]
            XCTAssertTrue(header.waitForExistence(timeout: 5))
            header.tap()
            header.typeText("Name")
            let value = app.textFields["table-cell-1-0"]
            value.tap()
            value.typeText("Touch edit")
            app.buttons["table-exit"].tap()
            editor.typeText("After table")
            XCTAssertEqual(value.value as? String, "Touch edit")
            XCTAssertTrue((editor.value as? String)?.hasSuffix("After table") == true)
        }

        func testSecondReturnExitsTaskAndQuoteOnTouchEditor() {
            newNote()
            for character in "[] " { editor.typeText(String(character)) }
            editor.typeText("Task")
            editor.typeText("\n")
            XCTAssertEqual(editor.value as? String, "Task\n", "第一次 Return 后应保留空待办；label=\(editor.label)")
            editor.typeText("\n")
            XCTAssertEqual(editor.value as? String, "Task\n", "第二次 Return 应退出空待办；label=\(editor.label)")
            editor.typeText("Body")
            expectText("Task\nBody")

            editor.typeText("\n")
            for character in "> " { editor.typeText(String(character)) }
            editor.typeText("Quote")
            editor.typeText("\n")
            editor.typeText("\n")
            editor.typeText("After quote")
            expectText("Task\nBody\nQuote\nAfter quote")
        }
    #endif

    #if os(macOS)
        func testSecondReturnExitsEmptyBulletItem() {
            newNote()
            for character in "- " { editor.typeText(String(character)) }
            editor.typeText("First")
            editor.typeKey(.escape, modifierFlags: [])
            editor.typeText("\n")
            editor.typeText("\n")
            editor.typeText("Body")
            expectText("• First\nBody")
        }

        func testSecondReturnExitsEmptyTaskItem() {
            newNote()
            for character in "[] " { editor.typeText(String(character)) }
            editor.typeText("Task")
            editor.typeKey(.escape, modifierFlags: [])
            editor.typeText("\n")
            editor.typeText("\n")
            editor.typeText("Body")
            expectText("Task\nBody")
        }

        func testSecondReturnExitsQuoteBeforeFollowingBody() {
            newNote()
            for character in "> " { editor.typeText(String(character)) }
            editor.typeText("1")
            editor.typeKey(.escape, modifierFlags: [])
            editor.typeText("\n")
            editor.typeText("\n")
            editor.typeText("Body")
            expectText("1\nBody")
            XCTAssertEqual(copiedMarkdown(), "> 1\n\nBody")
        }

        func testBackspaceOnEmptiedHeadingClearsHeadingStyle() {
            newNote()
            for character in "# " { editor.typeText(String(character)) }
            editor.typeText("Heading")
            editor.typeKey("a", modifierFlags: .command)
            editor.typeKey(.delete, modifierFlags: [])
            editor.typeKey(.delete, modifierFlags: [])
            editor.typeText("Body")
            expectText("Body")
            XCTAssertEqual(copiedMarkdown(), "Body")
        }

        func testDeletingInlineCodeContentClearsTypingStyle() {
            newNote()
            editor.typeText("`")
            editor.typeText("code")
            editor.typeText("`")
            expectText("code")
            editor.typeKey("a", modifierFlags: .command)
            editor.typeKey(.delete, modifierFlags: [])
            editor.typeText("next")
            expectText("next")
            XCTAssertEqual(copiedMarkdown(), "next")
        }

        func testTableEditsInlineAndRestoresAfterRelaunch() {
            newNote()
            app.buttons["insert-table"].tap()
            let first = app.textFields["table-cell-0-0"]
            XCTAssertTrue(first.waitForExistence(timeout: 5))
            first.tap()
            first.typeText("Name")
            app.typeKey(.tab, modifierFlags: [])
            app.typeText("Value")
            app.typeKey(.tab, modifierFlags: [])
            app.typeText("Alpha")
            app.typeKey(.tab, modifierFlags: [])
            app.typeText("42")
            XCTAssertEqual(app.textFields["table-cell-0-1"].value as? String, "Value")
            XCTAssertEqual(app.textFields["table-cell-1-0"].value as? String, "Alpha")
            XCTAssertEqual(app.textFields["table-cell-1-1"].value as? String, "42")
            app.typeKey(.tab, modifierFlags: [])
            let added = app.textFields["table-cell-2-0"]
            XCTAssertTrue(added.waitForExistence(timeout: 5))
            app.typeText("Beta")
            XCTAssertEqual(added.value as? String, "Beta")
            app.buttons["table-exit"].tap()
            app.typeText("After table")
            XCTAssertTrue((editor.value as? String)?.hasSuffix("After table") == true)
            app.menuButtons["Markdown"].tap()
            app.menuItems["copy-markdown"].tap()
            let markdown = NSPasteboard.general.string(forType: .string) ?? ""
            XCTAssertTrue(markdown.contains("| Name | Value |"))
            XCTAssertTrue(markdown.contains("| Alpha | 42 |"))
            XCTAssertTrue(markdown.contains("| Beta |  |"))
            XCTAssertTrue(markdown.hasSuffix("After table"))
            app.terminate()
            app.launch()
            app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "note-row-")).firstMatch.tap()
            XCTAssertTrue(first.waitForExistence(timeout: 5))
            XCTAssertEqual(first.value as? String, "Name")
            XCTAssertEqual(app.textFields["table-cell-1-0"].value as? String, "Alpha")
            XCTAssertEqual(app.textFields["table-cell-2-0"].value as? String, "Beta")
            XCTAssertTrue((editor.value as? String)?.hasSuffix("After table") == true)
        }

        func testTableCutPastePreservesCellsAndCanUndo() {
            newNote()
            app.buttons["insert-table"].tap()
            let header = app.textFields["table-cell-0-0"]
            XCTAssertTrue(header.waitForExistence(timeout: 5))
            header.tap()
            header.typeText("Keep this table")
            app.buttons["table-exit"].tap()
            app.typeKey("a", modifierFlags: .command)
            app.typeKey("x", modifierFlags: .command)
            XCTAssertFalse(header.exists)
            app.typeKey("v", modifierFlags: .command)
            XCTAssertTrue(header.waitForExistence(timeout: 5))
            XCTAssertEqual(header.value as? String, "Keep this table")
            app.typeKey("z", modifierFlags: .command)
            XCTAssertFalse(header.exists)
            app.typeKey("z", modifierFlags: .command)
            XCTAssertTrue(header.waitForExistence(timeout: 5))
            XCTAssertEqual(header.value as? String, "Keep this table")
        }

        func testTableStructureAlignmentUndoAndRedo() {
            newNote()
            app.buttons["insert-table"].tap()
            let actions = app.menuButtons["table-actions"]
            XCTAssertTrue(actions.waitForExistence(timeout: 5))
            actions.tap()
            app.menuItems["在右侧插入列"].tap()
            let thirdColumn = app.textFields["table-cell-0-2"]
            XCTAssertTrue(thirdColumn.waitForExistence(timeout: 5))
            app.buttons["table-exit"].tap()
            app.typeKey("z", modifierFlags: .command)
            XCTAssertFalse(thirdColumn.exists)
            app.typeKey("z", modifierFlags: [.command, .shift])
            XCTAssertTrue(thirdColumn.waitForExistence(timeout: 5))
            thirdColumn.tap()
            thirdColumn.typeText("Total")
            app.menuButtons["table-alignment"].tap()
            app.menuItems["右对齐"].tap()
            app.menuButtons["Markdown"].tap()
            app.menuItems["copy-markdown"].tap()
            XCTAssertTrue(NSPasteboard.general.string(forType: .string)?.contains("| --- | --- | ---: |") == true)
            actions.tap()
            app.menuItems["删除当前列"].tap()
            XCTAssertFalse(thirdColumn.exists)
        }

        func testCodeLanguageIndentAndUndo() {
            newNote()
            for character in "```swift" { editor.typeText(String(character)) }
            editor.typeText("\nlet value = 42")
            expectText("let value = 42")
            XCTAssertTrue(app.menuButtons["code-language"].waitForExistence(timeout: 5))
            app.typeKey(.tab, modifierFlags: [])
            expectText("    let value = 42")
            app.typeKey("z", modifierFlags: .command)
            expectText("let value = 42")
            app.typeKey("z", modifierFlags: [.command, .shift])
            expectText("    let value = 42")
            editor.typeText("\nnext")
            expectText("    let value = 42\n    next")
            app.buttons["copy-code"].tap()
            XCTAssertEqual(NSPasteboard.general.string(forType: .string), "    let value = 42\n    next")
            app.menuButtons["code-language"].tap()
            app.menuItems["Python"].tap()
            app.menuButtons["Markdown"].tap()
            app.menuItems["copy-markdown"].tap()
            XCTAssertTrue(NSPasteboard.general.string(forType: .string)?.hasPrefix("```python\n") == true)
        }

        func testMarkdownFileImportCreatesRenderedNote() throws {
            let source = "# Imported document\n\n**Strong** and *emphasis*\n- [x] Done\n\n`literal`\n\n```\nlet value = 1\n```"
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("weave-import-\(UUID().uuidString).md")
            try source.write(to: file, atomically: true, encoding: .utf8)
            defer { try? FileManager.default.removeItem(at: file) }
            let importer = app.buttons["import-markdown"]
            if importer.waitForExistence(timeout: 2) {
                importer.tap()
            } else {
                let overflow = app.popUpButtons["更多工具栏项"]
                XCTAssertTrue(overflow.waitForExistence(timeout: 5))
                overflow.tap()
                let overflowImporter = app.menuItems["导入 Markdown…"]
                XCTAssertTrue(overflowImporter.waitForExistence(timeout: 5))
                overflowImporter.tap()
            }
            app.typeKey("g", modifierFlags: [.command, .shift])
            let path = app.textFields["PathTextField"]
            XCTAssertTrue(path.waitForExistence(timeout: 5))
            path.typeText(file.path)
            app.typeKey(.return, modifierFlags: [])
            let open = app.buttons["OKButton"]
            XCTAssertTrue(open.waitForExistence(timeout: 5))
            expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: open)
            waitForExpectations(timeout: 5)
            open.tap()
            XCTAssertTrue(editor.waitForExistence(timeout: 5))
            expectText("Imported document\nStrong and emphasis\nDone\nliteral\nlet value = 1")
        }

        func testStrikeShortcutUndoAndOrdinaryContinuation() {
            newNote()
            for character in "~~done~~" { editor.typeText(String(character)) }
            expectText("done")
            editor.typeKey("z", modifierFlags: .command)
            expectText("~~done~~")
            editor.typeKey("z", modifierFlags: [.command, .shift])
            expectText("done")
            editor.typeText(" next")
            expectText("done next")
        }
    #endif

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
