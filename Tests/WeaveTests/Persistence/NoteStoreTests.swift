import Foundation
import SwiftUI
import Testing

@testable import Weave

@MainActor
struct NoteStoreTests {
    @Test func importedRichTextCreatesSeparateDurableRecord() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NoteStore(directory: directory)
        store.createNote()
        let original = store.notes[0]
        let imported = MarkdownFormatting.render("# Imported\n**Strong**\n- [x] Done")
        store.createNote(richText: imported)
        #expect(store.notes.count == 2)
        #expect(store.notes[1] == original)
        #expect(store.notes[0].richText == imported)
        #expect(store.selectedID == store.notes[0].id)
        await store.flushPendingSave()
        #expect(NoteStore(directory: directory).notes == store.notes)
    }

    @Test func chineseNotesSurviveRestartWithStableIdentity() async throws {
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

        await store.flushPendingSave()
        let restored = NoteStore(directory: directory)
        #expect(restored.notes == store.notes)
        #expect(restored.notes.map(\.id) == [secondID, firstID])
        #expect(restored.notes.last?.title == "")
        #expect(restored.notes.last?.preview == "周末计划 去海边走走 🌊 带上相机")
        #expect(!restored.hasUnsavedChanges)
    }

    @Test func corruptedFileBlocksMutationAndCanBeReloadedAfterRepair() async throws {
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
        await store.flushPendingSave()
        #expect(store.notes.count == 1)
        #expect(NoteStore(directory: directory).notes == store.notes)
    }

    @Test func failedWritePreservesMemoryUntilRetrySucceeds() async throws {
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
        await store.flushPendingSave()
        #expect(store.hasUnsavedChanges)
        #expect(store.saveError != nil)
        store.reload()
        #expect(store.notes.first?.text == "尚未保存的中文内容")

        try FileManager.default.removeItem(at: directory)
        store.retrySave()
        await store.flushPendingSave()
        #expect(!store.hasUnsavedChanges)
        #expect(store.saveError == nil)
        #expect(NoteStore(directory: directory).notes == store.notes)
    }

    @Test func richFormattingSurvivesRestartAndPlainEditResetsIt() async throws {
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

        await store.flushPendingSave()
        let restored = NoteStore(directory: directory)
        #expect(restored.loadError == nil)
        let note = try #require(restored.notes.first)
        #expect(note.richText == document)
        #expect(
            note.richText[note.richText.startIndex..<note.richText.index(note.richText.startIndex, offsetByCharacters: 3)].font
                == .title.bold())
        #expect(note.title == "")
        #expect(note.preview == "标题 重点中文网站")
        restored.updateText(id: id, text: note.text)
        await restored.flushPendingSave()
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
        #expect(note.title == "旧版中文")
        #expect(note.richText == AttributedString())
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
            let invalid = Data(
                "[{\"id\":\"\(id.uuidString)\",\"text\":\"原文\",\"richText\":\(invalidRichText),\"createdAt\":0,\"updatedAt\":0}]".utf8)
            try invalid.write(to: file)
            let store = NoteStore(directory: directory)
            #expect(store.loadError != nil)
            store.createNote()
            store.updateRichText(id: id, text: AttributedString("不能覆盖"))
            store.retrySave()
            #expect(try Data(contentsOf: file) == invalid)
        }
    }

    @Test func formattingUndoRedoPersistsEachState() async throws {
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
        await store.flushPendingSave()
        #expect(NoteStore(directory: directory).notes.first?.richText == formatted)
        undoManager.undo()
        await store.flushPendingSave()
        #expect(NoteStore(directory: directory).notes.first?.richText == AttributedString("中文"))
        undoManager.redo()
        await store.flushPendingSave()
        #expect(NoteStore(directory: directory).notes.first?.richText == formatted)
    }

    @Test func rapidEditsPersistOnlyAfterTheLatestSnapshotCompletes() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NoteStore(directory: directory)
        store.createNote()
        let id = try #require(store.selectedID)
        for index in 0..<100 {
            store.updateText(id: id, text: "第 \(index) 次编辑")
        }

        await store.flushPendingSave()

        #expect(!store.hasUnsavedChanges)
        #expect(NoteStore(directory: directory).notes.first?.text == "第 99 次编辑")
    }

    @Test func independentTitlePersistsWithoutChangingBodyOrMarkdown() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NoteStore(directory: directory)
        let body = MarkdownFormatting.render("# 正文标题\n\n正文 **重点**")
        store.createNote(title: "文件名", richText: body)
        let id = try #require(store.selectedID)
        let markdown = MarkdownFormatting.serialize(body, context: EnvironmentValues().fontResolutionContext)
        store.updateTitle(id: id, title: "新标题\n第二行")
        await store.flushPendingSave()
        let restored = NoteStore(directory: directory)
        let note = try #require(restored.notes.first)
        #expect(note.title == "新标题 第二行")
        #expect(note.displayTitle == "新标题 第二行")
        #expect(note.markdownFilename == "新标题 第二行")
        #expect(note.richText == body)
        #expect(MarkdownFormatting.serialize(note.richText, context: EnvironmentValues().fontResolutionContext) == markdown)
        restored.updateTitle(id: id, title: "")
        await restored.flushPendingSave()
        let untitled = try #require(NoteStore(directory: directory).notes.first)
        #expect(untitled.title.isEmpty)
        #expect(untitled.displayTitle == "未命名记录")
        #expect(untitled.richText == body)
    }

    @Test func legacyRichTitleMigrationSeparatesTitleAndPreservesBody() throws {
        var note = Note(id: UUID(), text: "", createdAt: .now, updatedAt: .now)
        note.richText = MarkdownFormatting.render("# 原来的标题\n\n正文 **重点**")
        let encoded = try JSONEncoder().encode(note)
        var legacy = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacy.removeValue(forKey: "title")
        legacy.removeValue(forKey: "titleSeparated")
        let decoded = try JSONDecoder().decode(Note.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(decoded.title == "原来的标题")
        #expect(decoded.text == "正文 重点")
        #expect(decoded.id == note.id)
        #expect(decoded.createdAt == note.createdAt)
        #expect(decoded.updatedAt == note.updatedAt)
        let roundTrip = try JSONDecoder().decode(Note.self, from: JSONEncoder().encode(decoded))
        #expect(roundTrip == decoded)
    }

    @Test func legacyTitleMigrationPreservesRichBodyFormatting() throws {
        var title = AttributedString("  旧标题  \n")
        title.font = .title
        var body = AttributedString("正文")
        body.font = .body.bold()
        let original = title + body
        var note = Note(id: UUID(), text: "", createdAt: .now, updatedAt: .now)
        note.richText = original
        var encoded = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(note)) as? [String: Any])
        encoded.removeValue(forKey: "title")
        encoded.removeValue(forKey: "titleSeparated")
        let decoded = try JSONDecoder().decode(Note.self, from: JSONSerialization.data(withJSONObject: encoded))
        #expect(decoded.title == "旧标题")
        #expect(decoded.text == "正文")
        #expect(decoded.richText.font == .body.bold())
    }

    @Test func transitionalTitleStorageCompletesSeparationOnce() throws {
        let note = Note(id: UUID(), text: "旧标题\n正文", createdAt: .now, updatedAt: .now, title: "旧标题")
        let encoded = try JSONEncoder().encode(note)
        var transitional = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        transitional.removeValue(forKey: "titleSeparated")
        let migrated = try JSONDecoder().decode(Note.self, from: JSONSerialization.data(withJSONObject: transitional))
        #expect(migrated.title == "旧标题")
        #expect(migrated.text == "正文")
        let stable = try JSONDecoder().decode(Note.self, from: JSONEncoder().encode(migrated))
        #expect(stable == migrated)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("WeaveTests-\(UUID().uuidString)", isDirectory: true)
    }
}
