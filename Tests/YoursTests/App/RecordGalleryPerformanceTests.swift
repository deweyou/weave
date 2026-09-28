import AppKit
import CoreText
import SwiftUI
import Testing

@testable import Yours

@MainActor
struct RecordGalleryPerformanceTests {
    private var typography: RecordCardTypography {
        let context = EnvironmentValues().fontResolutionContext
        return RecordCardTypography(
            title: Font.headline.resolve(in: context), summary: Font.subheadline.resolve(in: context),
            caption: Font.caption.resolve(in: context), minimumHeight: 120, maximumHeight: 320)
    }

    private func previews(count: Int) -> [RecordCardPreview] {
        (0..<count).map { index in
            RecordCardPreview(
                note: Note(
                    id: UUID(), text: String(repeating: "中文与 emoji 👨‍👩‍👧‍👦 mixed text\n", count: index % 12 + 1),
                    createdAt: .distantPast, updatedAt: .distantPast, title: "记录 \(index)"))
        }
    }

    @Test(arguments: [1_000, 10_000])
    func scrollingDoesNotRemeasureCards(count: Int) {
        let layout = RecordGalleryLayout()
        let previews = previews(count: count)
        _ = layout.update(previews: previews, typography: typography)
        let clock = ContinuousClock()
        let start = clock.now
        layout.prepare(width: 1000, minimumColumnWidth: 220)
        let prepareTime = start.duration(to: clock.now)
        #expect(layout.measurementCount == count)
        let measurements = layout.measurementCount
        let scrollStart = clock.now
        var maximumVisible = 0
        for step in 0..<1000 {
            layout.prepare(width: 1000, minimumColumnWidth: 220)
            let y = CGFloat(step) / 1000 * layout.index.contentSize.height
            maximumVisible = max(maximumVisible, layout.index.items(in: CGRect(x: 0, y: y, width: 1000, height: 720)).count)
        }
        #expect(layout.measurementCount == measurements)
        #expect(maximumVisible > 0 && maximumVisible < 40)
        print(
            "Gallery performance: \(count) cards, prepare \(prepareTime), 1000 viewport queries \(scrollStart.duration(to: clock.now)), maximum visible \(maximumVisible)"
        )
    }

    @Test func updatesReuseHeightsAndInvalidateForWidthAndTypography() {
        let layout = RecordGalleryLayout()
        var previews = previews(count: 100)
        _ = layout.update(previews: previews, typography: typography)
        layout.prepare(width: 1000, minimumColumnWidth: 220)
        previews.reverse()
        _ = layout.update(previews: previews, typography: typography)
        layout.prepare(width: 1000, minimumColumnWidth: 220)
        #expect(layout.measurementCount == 100)
        let original = previews[0]
        previews[0] = RecordCardPreview(
            note: Note(id: original.id, text: "Changed", createdAt: .distantPast, updatedAt: .now, title: "Edited"))
        _ = layout.update(previews: previews, typography: typography)
        layout.prepare(width: 1000, minimumColumnWidth: 220)
        #expect(layout.measurementCount == 101)
        layout.prepare(width: 600, minimumColumnWidth: 220)
        #expect(layout.measurementCount == 201)
        let enlarged = RecordCardTypography(
            title: typography.title, summary: typography.summary, caption: typography.caption,
            minimumHeight: 240, maximumHeight: 640)
        _ = layout.update(previews: previews, typography: enlarged)
        layout.prepare(width: 600, minimumColumnWidth: 220)
        #expect(layout.measurementCount == 301)
        #expect(layout.index.frames.allSatisfy { $0.height >= 240 && $0.height <= 640 })
        _ = layout.update(previews: [], typography: typography)
        layout.prepare(width: 600, minimumColumnWidth: 220)
        #expect(layout.index.frames.isEmpty)
    }

    @Test func indexedQueriesMatchFullScanAcrossBoundariesAndResize() {
        for width: CGFloat in [100, 455, 456, 732, 1600] {
            let index = RecordMasonryIndex(
                layout: RecordMasonryLayout(minimumColumnWidth: 220), width: width,
                heights: (0..<1000).map { CGFloat(120 + ($0 * 137) % 201) })
            for y in stride(from: CGFloat(-100), through: index.contentSize.height + 100, by: 371) {
                let rect = CGRect(x: 0, y: y, width: width, height: 720)
                let expected = index.frames.indices.filter { index.frames[$0].intersects(rect) }
                #expect(index.items(in: rect) == expected)
            }
        }
    }

    @Test func nativeCollectionReusesViewsWhileScrollingThousandRecords() throws {
        _ = NSApplication.shared
        let notes = (0..<1000).map { index in
            Note(
                id: UUID(), text: String(repeating: "A measured card body. ", count: index % 20 + 1),
                createdAt: .distantPast, updatedAt: .distantPast, title: "Card \(index)")
        }
        let state = RecordGalleryScrollState()
        let gallery = NativeRecordGallery(notes: notes, scrollState: state, resetGeneration: 0, typography: typography) { note in
            AnyView(
                Button {
                } label: {
                    RecordCard(note: note)
                }.buttonStyle(.plain))
        }
        let coordinator = gallery.makeCoordinator()
        let scroll = gallery.makeScrollView(coordinator: coordinator)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 720), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = scroll
        gallery.update(scroll, coordinator: coordinator)
        scroll.layoutSubtreeIfNeeded()
        let collection = try #require(scroll.documentView as? NSCollectionView)
        collection.layoutSubtreeIfNeeded()
        #expect(collection.visibleItems().count > 0)
        #expect(coordinator.createdHostCount < 60)
        let measurements = coordinator.geometry.measurementCount
        for step in 1...30 {
            scroll.contentView.scroll(to: CGPoint(x: 0, y: CGFloat(step) * 500))
            scroll.reflectScrolledClipView(scroll.contentView)
            collection.layoutSubtreeIfNeeded()
            #expect(collection.visibleItems().count < 60)
        }
        #expect(coordinator.createdHostCount < 100, "Scrolling must reuse hosts, rather than retain a host per visited record")
        #expect(coordinator.geometry.measurementCount == measurements)
        #expect(state.offset > 0)
        #expect(scroll.contentView.bounds.minY > 0)
        let savedOffset = state.offset
        let restoredCoordinator = gallery.makeCoordinator()
        let restoredScroll = gallery.makeScrollView(coordinator: restoredCoordinator)
        window.contentView = restoredScroll
        gallery.update(restoredScroll, coordinator: restoredCoordinator)
        restoredScroll.layoutSubtreeIfNeeded()
        #expect(abs(restoredScroll.contentView.bounds.minY - savedOffset) < 1)
        #expect(restoredCoordinator.geometry.measurementCount == measurements, "Returning must reuse the measured heights")
        window.contentView = scroll
        let reset = NativeRecordGallery(notes: notes, scrollState: state, resetGeneration: 1, typography: typography, card: gallery.card)
        state.reset()
        reset.update(scroll, coordinator: coordinator)
        scroll.layoutSubtreeIfNeeded()
        #expect(scroll.contentView.bounds.minY == 0)
        print("Native gallery: \(coordinator.createdHostCount) hosts for 1000 records after 30 scrolls")
    }

    @Test func reusedCardsUpdateNativeAppearanceWithoutRemeasuring() throws {
        _ = NSApplication.shared
        let note = Note(id: UUID(), text: "主题切换", createdAt: .distantPast, updatedAt: .distantPast, title: "Theme")
        let state = RecordGalleryScrollState()
        var gallery = NativeRecordGallery(
            notes: [note], scrollState: state, resetGeneration: 0, typography: typography, colorScheme: .dark
        ) { note in
            AnyView(RecordCard(note: note))
        }
        let coordinator = gallery.makeCoordinator()
        let scroll = gallery.makeScrollView(coordinator: coordinator)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 720), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = scroll
        gallery.update(scroll, coordinator: coordinator)
        scroll.layoutSubtreeIfNeeded()
        let collection = try #require(scroll.documentView as? NSCollectionView)
        collection.layoutSubtreeIfNeeded()
        let item = try #require(collection.visibleItems().first)
        let host = try #require(item.view.subviews.first)
        let measurements = coordinator.geometry.measurementCount
        let hosts = coordinator.createdHostCount

        for scheme in [ColorScheme.dark, .light, .dark, .light] {
            gallery.colorScheme = scheme
            gallery.update(scroll, coordinator: coordinator)
            collection.layoutSubtreeIfNeeded()
            #expect(item.view.subviews.first === host)
            #expect(host.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == (scheme == .dark ? .darkAqua : .aqua))
            #expect(coordinator.geometry.measurementCount == measurements)
            #expect(coordinator.createdHostCount == hosts)
        }
    }

    @Test func cachedTextHeightMatchesCardContent() {
        _ = NSApplication.shared
        for text in ["Short", String(repeating: "中文与 emoji 👋 English text. ", count: 8), String(repeating: "Line\n", count: 40)] {
            let note = Note(id: UUID(), text: text, createdAt: .distantPast, updatedAt: .distantPast, title: "A card title")
            let host = NSHostingController(rootView: RecordCard(note: note).fixedSize(horizontal: false, vertical: true))
            for width: CGFloat in [160, 220, 340] {
                let actual = host.sizeThatFits(in: CGSize(width: width, height: 1000)).height
                let cached = typography.height(for: RecordCardPreview(note: note), width: width)
                print("Height comparison \(width): cached \(cached), SwiftUI \(actual)")
                #expect(abs(cached - actual) <= 3)
            }
        }
    }

    @Test func scrollResetIsExplicit() {
        let state = RecordGalleryScrollState()
        state.offset = 5000
        #expect(state.resetGeneration == 0)
        state.reset()
        #expect(state.offset == 0)
        #expect(state.resetGeneration == 1)
    }
}
