#if os(macOS)
    import AppKit
    import SwiftUI
    import Testing
    @testable import Weave

    @MainActor
    struct NativeTableOverlayTests {
        @Test func codeCopyReportsFailureAndSupportsRetry() {
            let model = CodeHeaderModel()
            model.literal = "let value = 42"
            var received: [String] = []
            model.writeClipboard = { text in
                received.append(text)
                return received.count > 1
            }
            model.copyCode()
            #expect(model.copyStatus == .failed)
            #expect(model.copyStatus.label == "复制失败，点击重试")
            let firstAttempt = model.copyAttempt
            model.copyCode()
            #expect(model.copyStatus == .copied)
            #expect(model.copyAttempt > firstAttempt)
            #expect(received == [model.literal, model.literal])
            model.resetCopyFeedback()
            #expect(model.copyStatus == .ready)
            model.copyCode()
            model.literal = "changed"
            #expect(model.copyStatus == .ready)
        }

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

        @Test(arguments: [false, true], [220.0, 560.0])
        func codeHeaderAlignsWithSurfaceAndText(quoted: Bool, width: Double) throws {
            let view = NSTextView(frame: CGRect(x: 0, y: 0, width: 600, height: 500))
            let container = try #require(view.textContainer)
            container.widthTracksTextView = false
            container.size = CGSize(width: width, height: 10_000)
            let layout = CodeLayoutManager()
            container.replaceLayoutManager(layout)
            let prefix = quoted ? "> " : ""
            let markdown = ["```swift", "let value = 42", "```"].map { prefix + $0 }.joined(separator: "\n")
            let native = NativeTextAttributes.native(
                MarkdownFormatting.render(markdown), context: EnvironmentValues().fontResolutionContext)
            view.textStorage?.setAttributedString(native)
            let overlay = CodeHeaderOverlayController()
            overlay.refresh(in: view, onLanguage: { _, _ in })
            let host = try #require(view.subviews.compactMap { $0 as? NSHostingView<CodeHeaderView> }.first)
            let glyphs = layout.glyphRange(forCharacterRange: NSRange(location: 0, length: native.length), actualCharacterRange: nil)
            let surface = layout.codeBackgroundRect(forGlyphRange: glyphs, in: container).offsetBy(
                dx: view.textContainerOrigin.x, dy: view.textContainerOrigin.y)
            #expect(abs(host.frame.minX - surface.minX) < 0.5)
            #expect(abs(host.frame.maxX - surface.maxX) < 0.5)
            let fragment = layout.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil)
            let textX = view.textContainerOrigin.x + fragment.minX + layout.location(forGlyphAt: 0).x
            #expect(abs(host.frame.minX + DocumentTypography.codeInset - textX) < 0.5)
        }

        @Test func codeHeaderControlsKeepHandCursorDuringTextViewMouseMovement() throws {
            let layout = CodeLayoutManager()
            let storage = NSTextStorage(
                attributedString: NativeTextAttributes.native(
                    MarkdownFormatting.render("```swift\nlet value = 42\n```"), context: EnvironmentValues().fontResolutionContext))
            let container = NSTextContainer(size: CGSize(width: 560, height: 1_000))
            storage.addLayoutManager(layout)
            layout.addTextContainer(container)
            let view = ReadingMacTextView(frame: CGRect(x: 0, y: 0, width: 600, height: 500), textContainer: container)
            let window = NSWindow(contentRect: view.frame, styleMask: .titled, backing: .buffered, defer: false)
            window.contentView = view
            let overlay = CodeHeaderOverlayController()
            overlay.refresh(in: view, onLanguage: { _, _ in })
            let host = try #require(view.subviews.compactMap { $0 as? CodeHeaderHostingView }.first)
            host.layoutSubtreeIfNeeded()
            defer { NSCursor.arrow.set() }
            for (x, expected) in [
                (DocumentTypography.codeInset + 12, NSCursor.pointingHand),
                (host.bounds.width - DocumentTypography.codeInset - 14, NSCursor.pointingHand),
                (host.bounds.midX, NSCursor.arrow),
            ] {
                let point = NSPoint(x: x, y: host.bounds.midY)
                #expect(host.cursor(at: point) == expected)
                let event = try #require(
                    NSEvent.mouseEvent(
                        with: .mouseMoved, location: host.convert(point, to: nil), modifierFlags: [], timestamp: 0,
                        windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0))
                view.mouseMoved(with: event)
                #expect(NSCursor.current == expected)
            }
        }

        @Test func consecutiveCodeHeadersKeepTheSameTopPadding() throws {
            let view = NSTextView(frame: CGRect(x: 0, y: 0, width: 600, height: 600))
            let container = try #require(view.textContainer)
            let layout = CodeLayoutManager()
            container.replaceLayoutManager(layout)
            let markdown = "```swift\nlet a = 1\n```\n```python\nx = 2\n```\nAfter"
            let native = NativeTextAttributes.native(
                MarkdownFormatting.render(markdown), context: EnvironmentValues().fontResolutionContext)
            view.textStorage?.setAttributedString(native)
            let overlay = CodeHeaderOverlayController()
            overlay.refresh(in: view, onLanguage: { _, _ in })
            let hosts = view.subviews.compactMap { $0 as? NSHostingView<CodeHeaderView> }.sorted { $0.frame.minY < $1.frame.minY }
            #expect(hosts.count == 2)
            var ranges: [NSRange] = []
            native.enumerateAttribute(.weaveCodeStyle, in: NSRange(location: 0, length: native.length)) { value, range, _ in
                if (value as? String)?.hasPrefix("block:") == true { ranges.append(range) }
            }
            var previousBottom: CGFloat?
            for (host, range) in zip(hosts, ranges) {
                let glyphs = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                let surface = layout.codeBackgroundRect(forGlyphRange: glyphs, in: container).offsetBy(
                    dx: view.textContainerOrigin.x, dy: view.textContainerOrigin.y)
                #expect(surface.minY >= view.textContainerOrigin.y)
                #expect(abs(host.frame.minY - surface.minY - CodeLayoutManager.codeTopPadding) < 0.5)
                let used = layout.lineFragmentUsedRect(forGlyphAt: glyphs.location, effectiveRange: nil)
                #expect(abs(host.frame.maxY - used.minY - view.textContainerOrigin.y) < 0.5)
                if let previousBottom { #expect(surface.minY >= previousBottom) }
                previousBottom = surface.maxY
            }
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
