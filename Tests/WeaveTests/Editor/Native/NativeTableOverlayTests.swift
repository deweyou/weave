#if os(macOS)
    import AppKit
    import SwiftUI
    import Testing
    @testable import Weave

    @MainActor
    struct NativeTableOverlayTests {
        private func editor(_ table: TableData) -> NSTextView {
            let view = NSTextView(frame: CGRect(x: 0, y: 0, width: 600, height: 500))
            view.textContainer?.widthTracksTextView = false
            view.textContainer?.size = CGSize(width: 560, height: 10_000)
            setTable(table, in: view)
            return view
        }

        private func setTable(_ table: TableData, in view: NSTextView, prefix: String = "") {
            var source = AttributedString(prefix)
            source.append(table.attributedText)
            source.append(AttributedString("\nAfter table"))
            view.textStorage?.setAttributedString(NativeTextAttributes.native(source, context: EnvironmentValues().fontResolutionContext))
        }

        private func hosts(in view: NSTextView) -> [NSHostingView<TableBlockView>] {
            view.subviews.compactMap { $0 as? NSHostingView<TableBlockView> }
        }

        @Test func codeHeaderStaysAboveTextAndReusesHostAcrossEdits() throws {
            let view = NSTextView(frame: CGRect(x: 0, y: 0, width: 600, height: 500))
            view.textContainer?.size = CGSize(width: 560, height: 10_000)
            view.textContainer?.replaceLayoutManager(CodeLayoutManager())
            let context = EnvironmentValues().fontResolutionContext
            let source = MarkdownFormatting.render("```swift\nlet value = 42\n```\nAfter")
            view.textStorage?.setAttributedString(NativeTextAttributes.native(source, context: context))
            let overlay = CodeHeaderOverlayController()
            var chosen: String?
            overlay.refresh(in: view, onLanguage: { _, language in chosen = language })
            let host = try #require(view.subviews.compactMap { $0 as? NSHostingView<CodeHeaderView> }.first)
            let bounds = view.layoutManager!.boundingRect(forGlyphRange: NSRange(location: 0, length: 1), in: view.textContainer!)
            #expect(host.frame.minY >= 0)
            #expect(host.frame.maxY <= bounds.maxY + view.textContainerOrigin.y)
            #expect(view.layoutManager!.location(forGlyphAt: 0).y >= CodeLayoutManager.headerHeight)
            #expect(host.rootView.model.language == "swift")
            #expect(host.rootView.model.literal == "let value = 42")
            host.rootView.model.onLanguage("python")
            #expect(chosen == "python")
            let originalFrame = host.frame
            overlay.refresh(in: view, onLanguage: { _, _ in })
            #expect(host.frame == originalFrame)
            #expect(view.subviews.compactMap { $0 as? NSHostingView<CodeHeaderView> }.first === host)
            view.textStorage?.setAttributedString(NSAttributedString(string: "Body"))
            overlay.refresh(in: view, onLanguage: { _, _ in })
            #expect(host.superview == nil)
        }

        @Test func tableOverlayReusesHostWhileContentAndDimensionsChange() throws {
            let initial = TableData(rows: [["Name", "Value"], ["First", "1"]])
            let view = editor(initial)
            let overlay = TableOverlayController()
            overlay.refresh(in: view, onChange: { _, _ in }, onExit: { _ in })
            let host = try #require(hosts(in: view).first)
            #expect(hosts(in: view).count == 1)
            #expect(host.frame.height == TableTextAttachment.height(for: initial))
            let afterGlyphs = view.layoutManager!.glyphRange(forCharacterRange: NSRange(location: 2, length: 1), actualCharacterRange: nil)
            let afterRect = view.layoutManager!.boundingRect(forGlyphRange: afterGlyphs, in: view.textContainer!)
            #expect(afterRect.minY + view.textContainerOrigin.y >= host.frame.maxY)
            let initialWidth = host.frame.width

            var changed = initial
            changed.rows[1][0] = "Edited"
            changed.insertRow(after: 1)
            setTable(changed, in: view)
            view.textContainer?.size.width = 420
            overlay.refresh(in: view, onChange: { _, _ in }, onExit: { _ in })

            #expect(hosts(in: view).count == 1)
            #expect(hosts(in: view).first === host)
            #expect(host.rootView.model.table == changed)
            #expect(host.frame.height == TableTextAttachment.height(for: changed))
            #expect(host.frame.width < initialWidth)

            view.textStorage?.setAttributedString(NSAttributedString(string: "Only text remains"))
            overlay.refresh(in: view, onChange: { _, _ in }, onExit: { _ in })
            #expect(hosts(in: view).isEmpty)
            #expect(host.superview == nil)
        }

        @Test func reusedOverlayCallsCurrentHandlersAndExitPosition() throws {
            let table = TableData()
            let view = editor(table)
            let overlay = TableOverlayController()
            var obsoleteHandlerCalled = false
            overlay.refresh(in: view, onChange: { _, _ in obsoleteHandlerCalled = true }, onExit: { _ in obsoleteHandlerCalled = true })
            let host = try #require(hosts(in: view).first)
            setTable(table, in: view, prefix: "Before\n")
            var changedID: UUID?
            var changedTable: TableData?
            var exitOffset: Int?
            overlay.refresh(
                in: view,
                onChange: {
                    changedID = $0
                    changedTable = $1
                }, onExit: { exitOffset = $0 })
            host.rootView.model.change { $0.rows[1][1] = "Updated" }
            host.rootView.model.onExit()

            #expect(!obsoleteHandlerCalled)
            #expect(changedID == table.id)
            #expect(changedTable?.rows[1][1] == "Updated")
            #expect(exitOffset == "Before\n".utf16.count + 1)
        }

        @Test func invalidTableAttributeDoesNotCreateOverlay() {
            let view = NSTextView()
            let source = NSAttributedString(string: "\u{FFFC}", attributes: [.weaveTable: Data("invalid".utf8)])
            view.textStorage?.setAttributedString(source)
            let overlay = TableOverlayController()
            overlay.refresh(in: view, onChange: { _, _ in }, onExit: { _ in })
            #expect(hosts(in: view).isEmpty)
        }

        @Test func tableModelPublishesStructuralEditsAndSkipsNoOpChanges() {
            var changes: [TableData] = []
            var exited = false
            let model = NativeTableModel(table: TableData(), onChange: { changes.append($0) }, onExit: { exited = true })
            model.change { $0.rows[0][0] = "Name" }
            model.change { $0.insertRow(after: 1) }
            model.change { $0.insertColumn(after: 1) }
            model.change { $0.alignments[2] = .right }
            #expect(changes.count == 4)
            #expect(changes.last?.rows.count == 3)
            #expect(changes.last?.alignments == [.left, .left, .right])
            model.change { $0.alignments[2] = .right }
            #expect(changes.count == 4)
            model.change { $0.removeRow(at: 1) }
            model.change { $0.removeColumn(at: 1) }
            #expect(changes.count == 6)
            #expect(model.table.rows.count == 2)
            #expect(model.table.alignments == [.left, .right])
            model.onExit()
            #expect(exited)
        }
    }
#endif
