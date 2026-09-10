import Foundation
import Testing
import SwiftUI
@testable import Weave

@MainActor
struct NoteStoreTests {
    @Test func chineseNotesSurviveRestartWithStableIdentity() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NoteStore(directory: directory)
        #expect(store.loadError == nil)
        store.createNote()
        let firstID = try #require(store.selectedID)
        store.updateText(id: firstID, text: "\n  周末计划  \n去海边走走 🌊\n带上相机")
        store.createNote()
        let secondID = try #require(store.selectedID)
        store.updateText(id: secondID, text: "写作灵感\n保持简单，慢慢生长。")

        let restored = NoteStore(directory: directory)
        #expect(restored.notes == store.notes)
        #expect(restored.notes.map(\.id) == [secondID, firstID])
        #expect(restored.notes.last?.title == "周末计划")
        #expect(restored.notes.last?.preview == "去海边走走 🌊 带上相机")
        #expect(!restored.hasUnsavedChanges)
    }

    @Test func corruptedFileBlocksMutationAndCanBeReloadedAfterRepair() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("notes.json")
        let corruptContent = Data("{损坏的记录".utf8)
        try corruptContent.write(to: file)

        let store = NoteStore(directory: directory)
        #expect(store.loadError != nil)
        store.createNote()
        store.updateText(id: UUID(), text: "不应覆盖")
        store.retrySave()
        #expect(store.notes.isEmpty)
        #expect(try Data(contentsOf: file) == corruptContent)

        try Data("[]".utf8).write(to: file)
        store.reload()
        #expect(store.loadError == nil)
        store.createNote()
        #expect(store.notes.count == 1)
        #expect(NoteStore(directory: directory).notes == store.notes)
    }

    @Test func failedWritePreservesMemoryUntilRetrySucceeds() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let directory = root.appendingPathComponent("storage")
        let store = NoteStore(directory: directory)
        // A file at the directory path reliably prevents writes without depending on permissions.
        try Data("blocked".utf8).write(to: directory)
        store.createNote()
        let id = try #require(store.selectedID)
        store.updateText(id: id, text: "尚未保存的中文内容")
        #expect(store.hasUnsavedChanges)
        #expect(store.saveError != nil)
        store.reload()
        #expect(store.notes.first?.text == "尚未保存的中文内容")

        try FileManager.default.removeItem(at: directory)
        store.retrySave()
        #expect(!store.hasUnsavedChanges)
        #expect(store.saveError == nil)
        #expect(NoteStore(directory: directory).notes == store.notes)
    }

    @Test func richFormattingSurvivesRestartAndPlainEditResetsIt() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NoteStore(directory: directory)
        store.createNote()
        let id = try #require(store.selectedID)
        var heading = AttributedString("标题\n")
        heading.font = .title.bold()
        var emphasis = AttributedString("重点中文")
        emphasis.font = .body.bold().italic()
        emphasis.foregroundColor = .red
        emphasis.underlineStyle = .single
        var link = AttributedString("网站")
        link.link = URL(string: "https://example.com")
        let document = heading + emphasis + link
        store.updateRichText(id: id, text: document)

        let restored = NoteStore(directory: directory)
        #expect(restored.loadError == nil)
        let note = try #require(restored.notes.first)
        #expect(note.richText == document)
        #expect(note.richText[note.richText.startIndex..<note.richText.index(note.richText.startIndex, offsetByCharacters: 3)].font == .title.bold())
        #expect(note.title == "标题")
        #expect(note.preview == "重点中文网站")
        restored.updateText(id: id, text: note.text)
        #expect(restored.notes.first?.richText == AttributedString(note.text))
        #expect(NoteStore(directory: directory).notes == restored.notes)
    }

    @Test func legacyPlainTextMigratesWithoutChangingIdentityOrDates() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let id = UUID()
        let legacy = "[{\"id\":\"\(id.uuidString)\",\"text\":\"旧版中文\",\"createdAt\":12,\"updatedAt\":34}]"
        try Data(legacy.utf8).write(to: directory.appendingPathComponent("notes.json"))
        let store = NoteStore(directory: directory)
        let note = try #require(store.notes.first)
        #expect(store.loadError == nil)
        #expect(note.id == id)
        #expect(note.richText == AttributedString("旧版中文"))
        #expect(note.createdAt == Date(timeIntervalSinceReferenceDate: 12))
        #expect(note.updatedAt == Date(timeIntervalSinceReferenceDate: 34))
    }

    @Test func corruptRichTextCannotFallBackAndOverwriteOriginal() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("notes.json")
        let id = UUID()
        for invalidRichText in ["null", "42", "{}", "\"different content\""] {
            let invalid = Data("[{\"id\":\"\(id.uuidString)\",\"text\":\"原文\",\"richText\":\(invalidRichText),\"createdAt\":0,\"updatedAt\":0}]".utf8)
            try invalid.write(to: file)
            let store = NoteStore(directory: directory)
            #expect(store.loadError != nil)
            store.createNote()
            store.updateRichText(id: id, text: AttributedString("不能覆盖"))
            store.retrySave()
            #expect(try Data(contentsOf: file) == invalid)
        }
    }

    @Test func formattingUndoRedoPersistsEachState() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NoteStore(directory: directory)
        store.createNote()
        let id = try #require(store.selectedID)
        store.updateText(id: id, text: "中文")
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        var formatted = AttributedString("中文")
        formatted.font = .body.bold()
        undoManager.beginUndoGrouping()
        store.applyRichEdit(id: id, text: formatted, undoManager: undoManager)
        undoManager.endUndoGrouping()
        #expect(NoteStore(directory: directory).notes.first?.richText == formatted)
        undoManager.undo()
        #expect(NoteStore(directory: directory).notes.first?.richText == AttributedString("中文"))
        undoManager.redo()
        #expect(NoteStore(directory: directory).notes.first?.richText == formatted)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("WeaveTests-\(UUID().uuidString)", isDirectory: true)
    }
}
