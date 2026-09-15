#if os(macOS)
import AppKit
import SwiftUI
import Testing
@testable import Weave

@MainActor
struct NativeInputTests {
    @Test func backspaceOnEmptyFirstHeadingReturnsToBody() {
        let (view, coordinator) = editor(MarkdownFormatting.render("# 标题"))
        view.delegate = coordinator
        view.setSelectedRange(NSRange(location: view.string.utf16.count, length: 0))

        for _ in view.string { view.doCommand(by: #selector(NSResponder.deleteBackward(_:))) }
        #expect(view.string.isEmpty)
        // Once the last character is gone there is no range to delete, so AppKit
        // sends another deleteBackward command without calling shouldChangeTextIn.
        view.doCommand(by: #selector(NSResponder.deleteBackward(_:)))
        #expect(view.string.isEmpty)
        #expect(view.selectedRange() == NSRange(location: 0, length: 0))
        #expect(view.typingAttributes[.weaveParagraphStyle] as? String == "body")
        #expect(view.typingAttributes[.weaveCodeStyle] == nil)
    }

    @Test func emptyDocumentDoesNotStartWithHeadingTypingStyle() {
        let (view, coordinator) = editor(AttributedString())
        coordinator.update(coordinator.parent)
        let role = view.typingAttributes[.weaveParagraphStyle] as? String
        #expect(role == nil || role == "body")
        #expect(view.typingAttributes[.weaveCodeStyle] == nil)
    }

    @Test func clickingBelowTrailingCodeEndsBlockAndPreservesCodeContent() throws {
        let context = EnvironmentValues().fontResolutionContext
        for suffix in ["", "\n"] {
            var source = AttributedString("let value = 1" + suffix)
            source.font = .body.monospaced()
            source[ParagraphStyleAttribute.self] = "code"
            source[CodeStyleAttribute.self] = "block:test"
            source[CodeLanguageAttribute.self] = "swift"
            let (view, coordinator) = editor(source)
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 500, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = view
            view.allowsUndo = true
            let undo = try #require(view.undoManager)
            undo.beginUndoGrouping()
            #expect(coordinator.exitTrailingCode())
            undo.endUndoGrouping()
            #expect(view.string == "let value = 1\n")
            #expect(view.typingAttributes[.weaveCodeStyle] == nil)
            #expect(view.typingAttributes[.weaveParagraphStyle] as? String == "body")
            #expect(view.selectedRange().location == view.string.utf16.count)
            let restored = NativeTextAttributes.rich(view.textStorage!)
            #expect(MarkdownFormatting.serialize(restored, context: context) == "```swift\nlet value = 1\n```\n")
            #expect(!coordinator.exitTrailingCode())
            undo.undo()
            #expect(view.string == String(source.characters))
            #expect(view.typingAttributes[.weaveCodeStyle] as? String == "block:test")
            undo.redo()
            #expect(view.string == "let value = 1\n")
            #expect(view.typingAttributes[.weaveCodeStyle] == nil)
        }
    }

    @Test func shiftReturnInsertsLineBreakWithoutChangingParagraphStyle() {
        let (view, coordinator) = editor(MarkdownFormatting.render("## Heading"))
        view.delegate = coordinator
        #expect(coordinator.textView(view, doCommandBy: #selector(NSResponder.insertLineBreak(_:))))
        #expect(view.string == "Heading\u{2028}")
        #expect(view.selectedRange().location == view.string.utf16.count)
        #expect(view.typingAttributes[.weaveParagraphStyle] as? String == "heading:2")
        let rich = NativeTextAttributes.rich(view.textStorage!)
        let markdown = MarkdownFormatting.serialize(rich, context: EnvironmentValues().fontResolutionContext)
        let restored = MarkdownFormatting.render(markdown)
        #expect(String(restored.characters) == view.string)
        #expect(restored.runs.allSatisfy { $0[ParagraphStyleAttribute.self] == "heading:2" })
    }

    @Test func oneTabIndentsTaskAndReturnKeepsTheSameDepth() throws {
        let (view, coordinator) = editor(MarkdownFormatting.render("- [x] Parent"))
        view.delegate = coordinator

        #expect(coordinator.textView(view, doCommandBy: #selector(NSResponder.insertTab(_:))))
        #expect(view.string == "\tParent")
        #expect(view.textStorage?.attribute(.weaveParagraphStyle, at: 0, effectiveRange: nil) as? String == "task")

        #expect(!coordinator.intercept(range: view.selectedRange(), replacement: "\n"))
        #expect(view.string == "\tParent\n\t")
        let nextLine = (view.string as NSString).range(of: "\n").location + 1
        #expect(view.textStorage?.attribute(.weaveParagraphStyle, at: nextLine, effectiveRange: nil) as? String == "task")
        #expect(String(view.string.dropFirst(nextLine)).prefix(while: { $0 == "\t" }).count == 1)
    }

    @Test func secondReturnOnEmptyBulletExitsToBody() {
        let (view, coordinator) = editor(MarkdownFormatting.render("- First"))
        view.delegate = coordinator

        #expect(!coordinator.intercept(range: view.selectedRange(), replacement: "\n"))
        #expect(view.string == "• First\n• ")
        #expect(view.typingAttributes[.weaveParagraphStyle] as? String == "bullet")

        #expect(!coordinator.intercept(range: view.selectedRange(), replacement: "\n"))
        #expect(view.string == "• First\n")
        #expect(view.typingAttributes[.weaveParagraphStyle] as? String == "body")

        view.insertText("Body", replacementRange: view.selectedRange())
        #expect(view.string == "• First\nBody")
    }

    @Test func secondReturnOnEmptyTaskExitsToBody() {
        let (view, coordinator) = editor(MarkdownFormatting.render("- [ ] Task"))
        view.delegate = coordinator

        #expect(!coordinator.intercept(range: view.selectedRange(), replacement: "\n"))
        #expect(view.string == "Task\n")
        #expect(view.typingAttributes[.weaveParagraphStyle] as? String == "task")

        #expect(!coordinator.intercept(range: view.selectedRange(), replacement: "\n"))
        #expect(view.string == "Task\n")
        #expect(view.typingAttributes[.weaveParagraphStyle] as? String == "body")

        view.insertText("Body", replacementRange: view.selectedRange())
        #expect(view.string == "Task\nBody")
    }

    private func editor(_ source: AttributedString) -> (NSTextView, NativeRichTextEditor.Coordinator) {
        var text = source
        var selection = AttributedTextSelection(insertionPoint: source.endIndex)
        let editor = NativeRichTextEditor(text: Binding(get: { text }, set: { text = $0 }), selection: Binding(get: { selection }, set: { selection = $0 }))
        let coordinator = editor.makeCoordinator()
        let view = NSTextView()
        let native = NativeTextAttributes.native(source, context: EnvironmentValues().fontResolutionContext)
        view.textStorage?.setAttributedString(native)
        view.setSelectedRange(NSRange(location: native.length, length: 0))
        if native.length > 0 { view.typingAttributes = native.attributes(at: native.length - 1, effectiveRange: nil) }
        coordinator.textView = view
        return (view, coordinator)
    }

    @Test func selectingBlankParagraphKeepsItsLayoutAndTypingMetrics() throws {
        let source = MarkdownFormatting.render("## Heading\n\n\nBody")
        let (view, coordinator) = editor(source)
        let offset = (view.string as NSString).range(of: "\n\n").location + 1
        let range = try #require(Range<AttributedString.Index>(NSRange(location: offset, length: 0), in: source))
        coordinator.parent.selection = AttributedTextSelection(insertionPoint: range.lowerBound)
        view.textContainer?.size = CGSize(width: 560, height: 10_000)
        let layout = try #require(view.layoutManager)
        let container = try #require(view.textContainer)
        let bodyRange = (view.string as NSString).range(of: "Body")
        let glyphs = layout.glyphRange(forCharacterRange: bodyRange, actualCharacterRange: nil)
        let bodyBefore = layout.boundingRect(forGlyphRange: glyphs, in: container)
        let before = try #require(view.textStorage?.attribute(.paragraphStyle, at: offset, effectiveRange: nil) as? NSParagraphStyle)
        coordinator.update(coordinator.parent)
        let typing = try #require(view.typingAttributes[.paragraphStyle] as? NSParagraphStyle)
        #expect(typing.lineSpacing == before.lineSpacing)
        #expect(typing.paragraphSpacing == before.paragraphSpacing)
        #expect(typing.paragraphSpacingBefore == before.paragraphSpacingBefore)
        #expect(layout.boundingRect(forGlyphRange: glyphs, in: container) == bodyBefore)
        #expect(view.selectedRange() == NSRange(location: offset, length: 0))
    }

    @Test func localCodeLanguageActionKeepsDocumentSelectionAndOtherBlocks() throws {
        let (view, coordinator) = editor(MarkdownFormatting.render("```swift\nlet x = 1\n```\nBody\n```json\ntrue\n```"))
        let original = view.string
        let body = (original as NSString).range(of: "Body")
        view.setSelectedRange(body)
        let id = try #require(view.textStorage?.attribute(.weaveCodeStyle, at: 0, effectiveRange: nil) as? String)
        coordinator.changeCodeLanguage(id: id, language: "python")
        #expect(view.string == original)
        #expect(view.selectedRange() == body)
        #expect(view.textStorage?.attribute(.weaveCodeLanguage, at: 0, effectiveRange: nil) as? String == "python")
        let second = (original as NSString).range(of: "true")
        #expect(view.textStorage?.attribute(.weaveCodeLanguage, at: second.location, effectiveRange: nil) as? String == "json")
    }

    @Test func codeLanguageAndHighlightsSurviveOnlyAsSemanticAttributes() throws {
        let rendered = MarkdownFormatting.render("```swift\n\nlet value = 42\n```")
        let context = EnvironmentValues().fontResolutionContext
        let native = NativeTextAttributes.native(rendered, context: context)
        #expect(native.attribute(.weaveSyntaxColor, at: 1, effectiveRange: nil) as? Bool == true)
        let rich = NativeTextAttributes.rich(native)
        #expect(rich.runs.allSatisfy { $0.foregroundColor == nil })
        #expect(MarkdownFormatting.serialize(rich, context: context).hasPrefix("```swift\n\n"))
        var note = Note(id: UUID(), text: "", createdAt: Date(), updatedAt: Date())
        note.richText = rich
        let restored = try JSONDecoder().decode(Note.self, from: JSONEncoder().encode(note))
        #expect(restored.richText.runs.first?[CodeLanguageAttribute.self] == "swift")
    }

    @Test func codeIndentSelectionCannotReplaceAdjacentBody() {
        let (view, coordinator) = editor(MarkdownFormatting.render("```swift\nlet x = 1\n```\nBody"))
        view.setSelectedRange(NSRange(location: 0, length: view.string.utf16.count))
        view.typingAttributes = view.textStorage!.attributes(at: 0, effectiveRange: nil)
        let original = view.string
        #expect(!coordinator.intercept(range: view.selectedRange(), replacement: "\t"))
        #expect(view.string == original)
    }

    @Test func codeNewlineContinuesIndentAndBlankIndentExits() {
        let (view, coordinator) = editor(MarkdownFormatting.render("```python\n    return 1\n```"))
        #expect(!coordinator.intercept(range: view.selectedRange(), replacement: "\n"))
        #expect(view.string == "    return 1\n    ")
        #expect(!coordinator.intercept(range: view.selectedRange(), replacement: "\n"))
        #expect(view.string == "    return 1\n")
        #expect(view.typingAttributes[.weaveCodeStyle] == nil)
        #expect(view.typingAttributes[.weaveCodeLanguage] == nil)
    }

    @Test func editingTableUpdatesPayloadAndDoesNotLeakIntoTyping() throws {
        let table = TableData()
        let (view, coordinator) = editor(table.attributedText + AttributedString("\n"))
        var updated = table
        updated.rows[0][0] = "Saved header"
        coordinator.changeTable(id: table.id, table: updated)
        let rich = NativeTextAttributes.rich(view.textStorage!)
        #expect(rich.runs.first?[TableAttribute.self]?.rows[0][0] == "Saved header")
        view.typingAttributes = view.textStorage!.attributes(at: 0, effectiveRange: nil)
        #expect(coordinator.intercept(range: view.selectedRange(), replacement: "x"))
        #expect(view.typingAttributes[.attachment] == nil)
        #expect(view.typingAttributes[.weaveTable] == nil)
    }

    @Test func strikeShortcutPreservesNextTypingAttributes() {
        let (view, coordinator) = editor(AttributedString("Text ~~done~"))
        #expect(!coordinator.intercept(range: view.selectedRange(), replacement: "~"))
        #expect(view.string == "Text done")
        #expect(view.textStorage?.attribute(.strikethroughStyle, at: 5, effectiveRange: nil) as? Int == NSUnderlineStyle.single.rawValue)
        #expect(view.typingAttributes[.strikethroughStyle] == nil)
    }

    @Test func headingReturnResetsTypingStyleWithoutChangingHeading() {
        let (view, coordinator) = editor(MarkdownFormatting.render("# 标题"))
        #expect(!coordinator.intercept(range: view.selectedRange(), replacement: "\n"))
        #expect(view.string == "标题\n")
        #expect(view.typingAttributes[.weaveParagraphStyle] as? String == "body")
        #expect(view.textStorage?.attribute(.weaveParagraphStyle, at: 0, effectiveRange: nil) as? String == "heading:1")
    }

    @Test func listBackspaceRemovesPrefixWithoutDeletingText() {
        let (view, coordinator) = editor(AttributedString("• 任务"))
        view.setSelectedRange(NSRange(location: 2, length: 0))
        #expect(!coordinator.intercept(range: NSRange(location: 1, length: 1), replacement: ""))
        #expect(view.string == "任务")
        #expect(view.selectedRange().location == 0)
    }

    @Test func secondReturnOnEmptyQuoteExitsAndClearsTheTrailingQuoteBoundary() {
        let (view, coordinator) = editor(MarkdownFormatting.render("> First"))
        view.delegate = coordinator
        view.setSelectedRange(NSRange(location: view.string.utf16.count, length: 0))

        #expect(!coordinator.intercept(range: view.selectedRange(), replacement: "\n"))
        #expect(view.string == "First\n")
        #expect(view.typingAttributes[.weaveQuote] as? Bool == true)
        #expect(!coordinator.intercept(range: view.selectedRange(), replacement: "\n"))
        #expect(view.string == "First\n")
        #expect(view.selectedRange() == NSRange(location: view.string.utf16.count, length: 0))
        #expect(view.typingAttributes[.weaveParagraphStyle] as? String == "body")
        #expect(view.typingAttributes[.weaveQuote] == nil)
        var quoteRange = NSRange()
        _ = view.textStorage?.attribute(.weaveQuote, at: 0, effectiveRange: &quoteRange)
        let storage = NSTextStorage(attributedString: view.textStorage!)
        let layout = CodeLayoutManager()
        let container = NSTextContainer(size: CGSize(width: 500, height: 10_000))
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        layout.ensureLayout(for: container)
        let glyphs = layout.glyphRange(forCharacterRange: quoteRange, actualCharacterRange: nil)
        let bar = layout.quoteBarRect(forGlyphRange: glyphs, in: container)
        #expect(bar.maxY <= layout.extraLineFragmentRect.minY)
    }

    @Test func secondReturnOnEmptyQuoteBeforeBodyClearsItsTerminatingBoundary() {
        let (view, coordinator) = editor(MarkdownFormatting.render("> First\nBody"))
        view.delegate = coordinator
        let firstLineEnd = (view.string as NSString).range(of: "\n").location
        view.setSelectedRange(NSRange(location: firstLineEnd, length: 0))

        #expect(!coordinator.intercept(range: view.selectedRange(), replacement: "\n"))
        #expect(view.string == "First\n\nBody")
        #expect(view.typingAttributes[.weaveQuote] as? Bool == true)
        #expect(!coordinator.intercept(range: view.selectedRange(), replacement: "\n"))
        #expect(view.string == "First\n\nBody")
        let blankBoundary = (view.string as NSString).range(of: "\n\n").location + 1
        #expect(view.selectedRange() == NSRange(location: blankBoundary, length: 0))
        #expect(view.typingAttributes[.weaveParagraphStyle] as? String == "body")
        #expect(view.typingAttributes[.weaveQuote] == nil)
        #expect(view.textStorage?.attribute(.weaveParagraphStyle, at: blankBoundary, effectiveRange: nil) as? String == "body")
        #expect(view.textStorage?.attribute(.weaveQuote, at: blankBoundary, effectiveRange: nil) == nil)

        let storage = NSTextStorage(attributedString: view.textStorage!)
        let layout = CodeLayoutManager()
        let container = NSTextContainer(size: CGSize(width: 500, height: 10_000))
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        layout.ensureLayout(for: container)
        var quoteRange = NSRange()
        _ = storage.attribute(.weaveQuote, at: 0, effectiveRange: &quoteRange)
        let quoteGlyphs = layout.glyphRange(forCharacterRange: quoteRange, actualCharacterRange: nil)
        let blankGlyph = layout.glyphIndexForCharacter(at: blankBoundary)
        #expect(layout.quoteBarRect(forGlyphRange: quoteGlyphs, in: container).maxY
                <= layout.lineFragmentRect(forGlyphAt: blankGlyph, effectiveRange: nil).minY)
    }

    @Test func backspaceOnEmptyQuoteContinuationMergesParagraphs() {
        let (view, coordinator) = editor(MarkdownFormatting.render("> First\n> "))
        view.delegate = coordinator
        view.setSelectedRange(NSRange(location: view.string.utf16.count, length: 0))

        #expect(view.string == "First\n")
        view.doCommand(by: #selector(NSResponder.deleteBackward(_:)))
        #expect(view.string == "First")
        #expect(view.selectedRange() == NSRange(location: view.string.utf16.count, length: 0))
        #expect(view.typingAttributes[.weaveQuote] as? Bool == true)
        #expect(MarkdownFormatting.serialize(NativeTextAttributes.rich(view.textStorage!), context: EnvironmentValues().fontResolutionContext) == "> First")
    }

    @Test func deletingAllQuoteTextKeepsTheEmptyQuoteTypingState() {
        let (view, coordinator) = editor(MarkdownFormatting.render("> 引用"))
        view.delegate = coordinator
        view.setSelectedRange(NSRange(location: view.string.utf16.count, length: 0))

        while !view.string.isEmpty { view.deleteBackward(nil) }

        #expect(view.string.isEmpty)
        #expect(view.typingAttributes[.weaveQuote] as? Bool == true)
        #expect(view.typingAttributes[.weaveParagraphStyle] as? String == "body")
        coordinator.update(coordinator.parent)
        #expect(view.typingAttributes[.weaveQuote] as? Bool == true)
        view.insertText("继续", replacementRange: view.selectedRange())
        #expect(view.textStorage?.attribute(.weaveQuote, at: 0, effectiveRange: nil) as? Bool == true)
    }

    @Test func backspaceOnAnEmptyQuoteExitsBeforeFollowingTextIsTyped() {
        let (view, coordinator) = editor(MarkdownFormatting.render("> 引用"))
        view.delegate = coordinator
        view.setSelectedRange(NSRange(location: view.string.utf16.count, length: 0))

        while !view.string.isEmpty { view.deleteBackward(nil) }
        #expect(view.typingAttributes[.weaveQuote] as? Bool == true)

        view.doCommand(by: #selector(NSResponder.deleteBackward(_:)))
        #expect(view.typingAttributes[.weaveQuote] == nil)
        #expect(view.typingAttributes[.weaveParagraphStyle] as? String == "body")

        view.insertText("正文", replacementRange: view.selectedRange())
        #expect(view.textStorage?.attribute(.weaveQuote, at: 0, effectiveRange: nil) == nil)
        #expect(view.textStorage?.attribute(.weaveParagraphStyle, at: 0, effectiveRange: nil) as? String == "body")
    }

    @Test func deletingLastQuoteCharacterRestoresQuoteFromStorageWhenAppKitDropsTypingState() {
        let (view, coordinator) = editor(MarkdownFormatting.render("> 1"))
        view.delegate = coordinator
        view.setSelectedRange(NSRange(location: 1, length: 0))
        view.typingAttributes.removeValue(forKey: .weaveQuote)

        #expect(!coordinator.intercept(range: NSRange(location: 0, length: 1), replacement: ""))
        #expect(view.string.isEmpty)
        #expect(view.typingAttributes[.weaveQuote] as? Bool == true)
        coordinator.update(coordinator.parent)
        #expect(view.typingAttributes[.weaveQuote] as? Bool == true)
    }

    @Test func readingTextViewPreservesQuoteAfterItsLastCharacterIsDeleted() {
        let source = MarkdownFormatting.render("> 1")
        var text = source
        var selection = AttributedTextSelection(insertionPoint: source.endIndex)
        let editor = NativeRichTextEditor(text: Binding(get: { text }, set: { text = $0 }), selection: Binding(get: { selection }, set: { selection = $0 }))
        let coordinator = editor.makeCoordinator()
        let view = ReadingMacTextView()
        let native = NativeTextAttributes.native(source, context: EnvironmentValues().fontResolutionContext)
        view.textStorage?.setAttributedString(native)
        view.setSelectedRange(NSRange(location: 1, length: 0))
        view.typingAttributes = native.attributes(at: 0, effectiveRange: nil)
        view.delegate = coordinator
        view.didResolveTypingAttributes = {
            coordinator.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification, object: view))
        }
        coordinator.textView = view

        view.deleteBackward(nil)
        coordinator.update(coordinator.parent)

        #expect(view.string.isEmpty)
        #expect(view.typingAttributes[.weaveQuote] as? Bool == true)
    }

    @Test func deletingLastQuoteCharacterKeepsTheBarGeometryStable() throws {
        let source = MarkdownFormatting.render("> 1")
        var text = source
        var selection = AttributedTextSelection(insertionPoint: source.endIndex)
        let editor = NativeRichTextEditor(
            text: Binding(get: { text }, set: { text = $0 }),
            selection: Binding(get: { selection }, set: { selection = $0 })
        )
        let coordinator = editor.makeCoordinator()
        let native = NativeTextAttributes.native(source, context: EnvironmentValues().fontResolutionContext)
        let storage = NSTextStorage(attributedString: native)
        let layout = CodeLayoutManager()
        let container = NSTextContainer(size: CGSize(width: 500, height: 10_000))
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        let view = ReadingMacTextView(
            frame: CGRect(x: 0, y: 0, width: 500, height: 320),
            textContainer: container
        )
        let window = NSWindow(
            contentRect: view.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        view.delegate = coordinator
        coordinator.textView = view
        view.setSelectedRange(NSRange(location: native.length, length: 0))
        view.typingAttributes = native.attributes(at: 0, effectiveRange: nil)
        layout.ensureLayout(for: container)

        let filled = layout.quoteBarRect(
            forGlyphRange: NSRange(location: 0, length: layout.numberOfGlyphs),
            in: container
        ).offsetBy(dx: view.textContainerOrigin.x, dy: view.textContainerOrigin.y)

        view.deleteBackward(nil)
        coordinator.update(coordinator.parent)
        let empty = try #require(view.emptyQuoteBarDrawingRect())

        #expect(view.string.isEmpty)
        #expect(abs(filled.minY - empty.minY) < 0.01)
        #expect(abs(filled.maxY - empty.maxY) < 0.01)
    }

    @Test func firstReturnExtendsOneQuoteBarThroughTheTrailingEmptyLine() throws {
        let source = MarkdownFormatting.render("> 1")
        var text = source
        var selection = AttributedTextSelection(insertionPoint: source.endIndex)
        let editor = NativeRichTextEditor(
            text: Binding(get: { text }, set: { text = $0 }),
            selection: Binding(get: { selection }, set: { selection = $0 })
        )
        let coordinator = editor.makeCoordinator()
        let native = NativeTextAttributes.native(source, context: EnvironmentValues().fontResolutionContext)
        let storage = NSTextStorage(attributedString: native)
        let layout = CodeLayoutManager()
        let container = NSTextContainer(size: CGSize(width: 500, height: 10_000))
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        let view = ReadingMacTextView(
            frame: CGRect(x: 0, y: 0, width: 500, height: 320),
            textContainer: container
        )
        let window = NSWindow(
            contentRect: view.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        view.delegate = coordinator
        coordinator.textView = view
        view.setSelectedRange(NSRange(location: native.length, length: 0))
        view.typingAttributes = native.attributes(at: 0, effectiveRange: nil)

        #expect(!coordinator.intercept(range: view.selectedRange(), replacement: "\n"))
        layout.ensureLayout(for: container)
        let empty = try #require(view.emptyQuoteBarDrawingRect())
        let glyphs = layout.glyphRange(
            forCharacterRange: NSRange(location: 0, length: storage.length),
            actualCharacterRange: nil
        )
        let bars = layout.quoteBarDrawingRects(
            forGlyphRange: glyphs,
            at: view.textContainerOrigin,
            trailingEmptyBar: empty
        )

        #expect(view.string == "1\n")
        #expect(bars.count == 1)
        #expect(bars[0].contains(empty))
        #expect(bars[0].minY < empty.minY)
    }

    @Test func secondReturnAtDocumentEndExitsTheTrailingEmptyQuote() throws {
        let frameInitializedView = ReadingMacTextView(frame: CGRect(x: 0, y: 0, width: 500, height: 320))
        #expect(frameInitializedView.subviews.count == 1)
        var text = AttributedString()
        var selection = AttributedTextSelection(insertionPoint: text.startIndex)
        let editor = NativeRichTextEditor(
            text: Binding(get: { text }, set: { text = $0 }),
            selection: Binding(get: { selection }, set: { selection = $0 })
        )
        let coordinator = editor.makeCoordinator()
        let storage = NSTextStorage()
        let layout = CodeLayoutManager()
        let container = NSTextContainer(size: CGSize(width: 500, height: 10_000))
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        let view = ReadingMacTextView(
            frame: CGRect(x: 0, y: 0, width: 500, height: 320),
            textContainer: container
        )
        let window = NSWindow(
            contentRect: view.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        view.delegate = coordinator
        coordinator.textView = view
        view.setSelectedRange(NSRange(location: 0, length: 0))
        var bodySample = AttributedString("\n")
        bodySample.font = .body
        bodySample[ParagraphStyleAttribute.self] = "body"
        let nativeBody = NativeTextAttributes.native(bodySample, context: EnvironmentValues().fontResolutionContext)
        view.typingAttributes = nativeBody.attributes(at: 0, effectiveRange: nil)

        layout.ensureLayout(for: container)
        let bodyExtraLineX = layout.extraLineFragmentUsedRect.minX
        view.insertText(">", replacementRange: view.selectedRange())
        view.insertText(" ", replacementRange: view.selectedRange())
        coordinator.update(coordinator.parent)
        let emptyQuoteStyle = try #require(view.typingAttributes[.paragraphStyle] as? NSParagraphStyle)
        #expect(view.string.isEmpty)
        #expect(emptyQuoteStyle.firstLineHeadIndent == DocumentTypography.quoteIndent)
        #expect(abs(layout.extraLineFragmentUsedRect.minX - bodyExtraLineX - DocumentTypography.quoteIndent) < 0.5)
        view.insertText("1", replacementRange: view.selectedRange())
        #expect(view.string == "1")
        #expect(view.typingAttributes[.weaveQuote] as? Bool == true)

        view.insertNewline(nil)
        coordinator.update(coordinator.parent)
        #expect(view.typingAttributes[.weaveQuote] as? Bool == true)
        #expect(view.emptyQuoteBarDrawingRect() != nil)
        let quotedSelection = selection
        view.insertNewline(nil)
        let staleParent = NativeRichTextEditor(
            text: Binding(get: { text }, set: { text = $0 }),
            selection: .constant(quotedSelection)
        )
        coordinator.update(staleParent)
        layout.ensureLayout(for: container)

        #expect(view.string == "1\n")
        #expect(view.selectedRange() == NSRange(location: 2, length: 0))
        #expect(view.typingAttributes[.weaveQuote] == nil)
        #expect(view.emptyQuoteBarDrawingRect() == nil)
        let bodyTypingStyle = try #require(view.typingAttributes[.paragraphStyle] as? NSParagraphStyle)
        #expect(bodyTypingStyle.firstLineHeadIndent == 0)
        #expect(bodyTypingStyle.headIndent == 0)
        view.insertText("Body", replacementRange: view.selectedRange())
        let insertedStyle = try #require(storage.attribute(.paragraphStyle, at: 2, effectiveRange: nil) as? NSParagraphStyle)
        #expect(insertedStyle.firstLineHeadIndent == 0)
        #expect(insertedStyle.headIndent == 0)
        layout.ensureLayout(for: container)
        let bodyGlyph = layout.glyphIndexForCharacter(at: 2)
        let bodyLine = layout.lineFragmentRect(forGlyphAt: bodyGlyph, effectiveRange: nil)
        let glyphs = layout.glyphRange(
            forCharacterRange: NSRange(location: 0, length: storage.length),
            actualCharacterRange: nil
        )
        let bars = layout.quoteBarDrawingRects(forGlyphRange: glyphs, at: view.textContainerOrigin)
        #expect(bars.count == 1)
        #expect(bars[0].maxY <= bodyLine.minY + view.textContainerOrigin.y)
    }

    @Test func emptyTaskShortcutInsideQuoteDrawsARealCheckboxWithoutPlaceholderText() throws {
        let source = MarkdownFormatting.render("> 1")
        var text = source
        var selection = AttributedTextSelection(insertionPoint: source.endIndex)
        let editor = NativeRichTextEditor(
            text: Binding(get: { text }, set: { text = $0 }),
            selection: Binding(get: { selection }, set: { selection = $0 })
        )
        let coordinator = editor.makeCoordinator()
        let native = NativeTextAttributes.native(source, context: EnvironmentValues().fontResolutionContext)
        let storage = NSTextStorage(attributedString: native)
        let layout = CodeLayoutManager()
        let container = NSTextContainer(size: CGSize(width: 500, height: 10_000))
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        let view = ReadingMacTextView(
            frame: CGRect(x: 0, y: 0, width: 500, height: 320),
            textContainer: container
        )
        let window = NSWindow(
            contentRect: view.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        view.delegate = coordinator
        coordinator.textView = view
        view.setSelectedRange(NSRange(location: native.length, length: 0))
        view.typingAttributes = native.attributes(at: 0, effectiveRange: nil)

        #expect(!coordinator.intercept(range: view.selectedRange(), replacement: "\n"))
        view.insertText("[", replacementRange: view.selectedRange())
        view.insertText("]", replacementRange: view.selectedRange())
        view.insertText(" ", replacementRange: view.selectedRange())
        layout.ensureLayout(for: container)

        let marker = try #require(view.emptyTaskMarkerDrawingRect())
        let quote = try #require(view.emptyQuoteBarDrawingRect())
        #expect(view.string == "1\n")
        #expect(!view.string.contains("☐"))
        #expect(view.typingAttributes[.weaveParagraphStyle] as? String == "task")
        #expect(view.typingAttributes[.weaveQuote] as? Bool == true)
        #expect(view.typingAttributes[.weaveTaskChecked] as? Bool == false)
        #expect(marker.minX > quote.maxX)
        #expect(coordinator.toggleEmptyTask())
        #expect(view.typingAttributes[.weaveTaskChecked] as? Bool == true)
    }

    @Test func firstDocumentLineKeepsQuoteBarGeometryWhenAnEmptyTaskGetsText() throws {
        var text = AttributedString()
        var selection = AttributedTextSelection(insertionPoint: text.startIndex)
        let editor = NativeRichTextEditor(
            text: Binding(get: { text }, set: { text = $0 }),
            selection: Binding(get: { selection }, set: { selection = $0 })
        )
        let coordinator = editor.makeCoordinator()
        let storage = NSTextStorage()
        let layout = CodeLayoutManager()
        let container = NSTextContainer(size: CGSize(width: 500, height: 10_000))
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        let view = ReadingMacTextView(
            frame: CGRect(x: 0, y: 0, width: 500, height: 320),
            textContainer: container
        )
        let window = NSWindow(
            contentRect: view.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        var body = AttributedString(" ")
        body.font = .body
        body[ParagraphStyleAttribute.self] = "body"
        view.typingAttributes = NativeTextAttributes.native(
            body,
            context: EnvironmentValues().fontResolutionContext
        ).attributes(at: 0, effectiveRange: nil)
        view.delegate = coordinator
        coordinator.textView = view

        for character in "> [] " {
            view.insertText(String(character), replacementRange: view.selectedRange())
        }
        layout.ensureLayout(for: container)
        let immediateEmptyBar = try #require(view.emptyQuoteBarDrawingRect())
        coordinator.update(coordinator.parent)
        layout.ensureLayout(for: container)
        let emptyBar = try #require(view.emptyQuoteBarDrawingRect())

        view.insertText("1", replacementRange: view.selectedRange())
        layout.ensureLayout(for: container)
        let immediateGlyphs = layout.glyphRange(
            forCharacterRange: NSRange(location: 0, length: storage.length),
            actualCharacterRange: nil
        )
        let immediateFilledBar = layout.quoteBarRect(
            forGlyphRange: immediateGlyphs,
            in: container
        ).offsetBy(dx: view.textContainerOrigin.x, dy: view.textContainerOrigin.y)
        coordinator.update(coordinator.parent)
        layout.ensureLayout(for: container)
        let glyphs = layout.glyphRange(
            forCharacterRange: NSRange(location: 0, length: storage.length),
            actualCharacterRange: nil
        )
        let filledBar = layout.quoteBarRect(forGlyphRange: glyphs, in: container).offsetBy(
            dx: view.textContainerOrigin.x,
            dy: view.textContainerOrigin.y
        )

        #expect(abs(immediateEmptyBar.minY - emptyBar.minY) < 0.01)
        #expect(abs(immediateEmptyBar.maxY - emptyBar.maxY) < 0.01)
        #expect(abs(emptyBar.minY - immediateFilledBar.minY) < 0.01)
        #expect(abs(emptyBar.maxY - immediateFilledBar.maxY) < 0.01)
        #expect(abs(emptyBar.minY - filledBar.minY) < 0.01)
        #expect(abs(emptyBar.maxY - filledBar.maxY) < 0.01)
    }

    @Test func commandBackspaceRestoresEmptyQuoteAfterAppKitChangesTheText() {
        let (view, coordinator) = editor(MarkdownFormatting.render("> 1"))
        view.delegate = coordinator
        view.setSelectedRange(NSRange(location: 1, length: 0))

        view.doCommand(by: #selector(NSResponder.deleteBackward(_:)))
        coordinator.update(coordinator.parent)

        #expect(view.string.isEmpty)
        #expect(view.typingAttributes[.weaveQuote] as? Bool == true)
    }

    @Test func textDidChangeRestoresQuoteFromThePreviousNativeSnapshot() {
        let (view, coordinator) = editor(MarkdownFormatting.render("> 1"))
        view.delegate = coordinator
        coordinator.update(coordinator.parent)
        view.textStorage?.deleteCharacters(in: NSRange(location: 0, length: 1))
        view.setSelectedRange(NSRange(location: 0, length: 0))
        view.typingAttributes.removeValue(forKey: .weaveQuote)

        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: view))
        coordinator.update(coordinator.parent)

        #expect(view.string.isEmpty)
        #expect(view.typingAttributes[.weaveQuote] as? Bool == true)
    }

    @Test(arguments: ["`code`", "**bold**", "*italic*", "~~strike~~"])
    func deletingAnEntireInlineFormatResetsFollowingTyping(source: String) {
        let (view, coordinator) = editor(MarkdownFormatting.render(source))
        view.delegate = coordinator
        view.setSelectedRange(NSRange(location: view.string.utf16.count, length: 0))

        while !view.string.isEmpty { view.deleteBackward(nil) }
        #expect(view.string.isEmpty)
        view.insertText("next", replacementRange: view.selectedRange())
        #expect(view.string == "next")
        #expect(view.textStorage?.attribute(.weaveCodeStyle, at: 0, effectiveRange: nil) == nil)
        #expect((view.textStorage?.attribute(.weaveInlineEmphasis, at: 0, effectiveRange: nil) as? Int ?? 0) == 0)
        #expect((view.textStorage?.attribute(.strikethroughStyle, at: 0, effectiveRange: nil) as? Int ?? 0) == 0)
    }

    @Test func codeEntryAndEmptyLineExitKeepNativeTypingState() {
        let (view, coordinator) = editor(AttributedString("```swift"))
        #expect(!coordinator.intercept(range: view.selectedRange(), replacement: "\n"))
        #expect(view.string.isEmpty)
        #expect((view.typingAttributes[.weaveCodeStyle] as? String)?.hasPrefix("block:") == true)
        #expect(!coordinator.intercept(range: view.selectedRange(), replacement: "\n"))
        #expect(view.typingAttributes[.weaveCodeStyle] == nil)
    }

    @Test func markdownShortcutsInsideQuoteKeepTheOuterQuote() {
        for (syntax, expectedRole) in [("-", "bullet"), ("1.", "numbered"), ("- [ ]", "task")] {
            let (view, coordinator) = editor(AttributedString())
            view.delegate = coordinator
            for character in "> " + syntax + " " {
                view.insertText(String(character), replacementRange: view.selectedRange())
            }
            #expect(view.typingAttributes[.weaveQuote] as? Bool == true)
            #expect(view.typingAttributes[.weaveParagraphStyle] as? String == expectedRole)
            view.insertText("内容", replacementRange: view.selectedRange())
            #expect(view.textStorage?.attribute(.weaveQuote, at: 0, effectiveRange: nil) as? Bool == true)
            #expect(view.textStorage?.attribute(.weaveParagraphStyle, at: 0, effectiveRange: nil) as? String == expectedRole)
        }

        let (codeView, codeCoordinator) = editor(AttributedString())
        codeView.delegate = codeCoordinator
        for character in "> ```swift" {
            codeView.insertText(String(character), replacementRange: codeView.selectedRange())
        }
        #expect(!codeCoordinator.intercept(range: codeView.selectedRange(), replacement: "\n"))
        #expect(codeView.string.isEmpty)
        #expect(codeView.typingAttributes[.weaveQuote] as? Bool == true)
        #expect((codeView.typingAttributes[.weaveCodeStyle] as? String)?.hasPrefix("block:") == true)
    }

    @Test func pastedURLKeepsSelectedLabel() {
        let (view, coordinator) = editor(AttributedString("网站"))
        view.setSelectedRange(NSRange(location: 0, length: 2))
        #expect(!coordinator.intercept(range: view.selectedRange(), replacement: "https://apple.com"))
        #expect(view.string == "网站")
        #expect(view.textStorage?.attribute(.link, at: 0, effectiveRange: nil) as? URL == URL(string: "https://apple.com"))
    }

    @Test func adjacentInlineCodeShortcutPreservesHeadingAndSurroundingText() {
        for role in ["body", "heading:1"] {
            var source = AttributedString("\u{624B}\u{518C}`value\u{540E}")
            source[ParagraphStyleAttribute.self] = role
            source.font = ParagraphEditing.font(for: role)
            let (view, coordinator) = editor(source)
            view.setSelectedRange(NSRange(location: 8, length: 0))
            #expect(!coordinator.intercept(range: view.selectedRange(), replacement: "`"))
            #expect(view.string == "\u{624B}\u{518C}value\u{540E}")
            #expect(view.textStorage!.attribute(.weaveCodeStyle, at: 2, effectiveRange: nil) as? String == "inline")
            #expect(view.textStorage!.attribute(.weaveCodeStyle, at: 0, effectiveRange: nil) == nil)
            #expect(view.textStorage!.attribute(.weaveCodeStyle, at: 7, effectiveRange: nil) == nil)
            #expect(view.textStorage!.attribute(.weaveParagraphStyle, at: 2, effectiveRange: nil) as? String == role)
            #expect(view.typingAttributes[.weaveCodeStyle] == nil)
        }
    }

    @Test func adjacentItalicAndStrikeShortcutsPreserveSurroundingText() {
        for role in ["body", "heading:1"] {
            for marker in ["*", "~~"] {
                for suffix in ["后文", "`code`"] {
                    let before = "正文😀" + marker + "内容" + marker.dropLast()
                    var source = AttributedString(before + suffix)
                    source[ParagraphStyleAttribute.self] = role
                    source.font = ParagraphEditing.font(for: role)
                    let (view, coordinator) = editor(source)
                    view.setSelectedRange(NSRange(location: before.utf16.count, length: 0))
                    #expect(!coordinator.intercept(range: view.selectedRange(), replacement: String(marker.last!)))
                    #expect(view.string == "正文😀内容" + suffix)
                    #expect(view.selectedRange() == NSRange(location: 6, length: 0))
                    #expect(view.textStorage!.attribute(.weaveParagraphStyle, at: 4, effectiveRange: nil) as? String == role)
                    if marker == "*" {
                        #expect((view.textStorage!.attribute(.weaveInlineEmphasis, at: 4, effectiveRange: nil) as? Int ?? 0) & 2 == 2)
                        #expect((view.typingAttributes[.weaveInlineEmphasis] as? Int ?? 0) & 2 == 0)
                    } else {
                        #expect(view.textStorage!.attribute(.strikethroughStyle, at: 4, effectiveRange: nil) as? Int == NSUnderlineStyle.single.rawValue)
                        #expect((view.typingAttributes[.strikethroughStyle] as? Int ?? 0) == 0)
                    }
                }
            }
        }
    }

    @Test func boldShortcutAfterChineseTextOnlyFormatsMarkedContent() {
        let (view, coordinator) = editor(AttributedString("正文**加粗*"))
        #expect(!coordinator.intercept(range: view.selectedRange(), replacement: "*"))
        #expect(view.string == "正文加粗")
        let font = view.textStorage!.attribute(.font, at: 2, effectiveRange: nil) as! NSFont
        #expect(NSFontManager.shared.traits(of: font).contains(.boldFontMask))
        let bodyFont = view.typingAttributes[.font] as! NSFont
        #expect(!NSFontManager.shared.traits(of: bodyFont).contains(.boldFontMask))
    }

    @Test func exitingPopulatedCodeBlockPersistsBodyBoundary() {
        var source = AttributedString("let value = 1\n")
        source.font = .body.monospaced()
        source[CodeStyleAttribute.self] = "block:test"
        source[ParagraphStyleAttribute.self] = "code"
        let (view, coordinator) = editor(source)
        #expect(!coordinator.intercept(range: view.selectedRange(), replacement: "\n"))
        #expect(view.typingAttributes[.weaveCodeStyle] == nil)
        let boundary = view.textStorage!.length - 1
        #expect(view.textStorage!.attribute(.weaveCodeStyle, at: boundary, effectiveRange: nil) == nil)
        #expect(view.textStorage!.attribute(.weaveCodeStyle, at: 0, effectiveRange: nil) as? String == "block:test")
    }
}
#endif
