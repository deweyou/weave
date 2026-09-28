import SwiftUI

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

struct RecordGallery<Card: View>: View {
    let notes: [Note]
    let scrollState: RecordGalleryScrollState
    @ViewBuilder let card: (Note) -> Card
    @Environment(\.self) private var environment
    @Environment(\.fontResolutionContext) private var fontContext
    #if os(macOS)
        @ScaledMetric private var minimumHeight = 120.0
        @ScaledMetric private var maximumHeight = 320.0
    #else
        @ScaledMetric private var minimumHeight = 112.0
        @ScaledMetric private var maximumHeight = 280.0
    #endif

    var body: some View {
        NativeRecordGallery(
            notes: notes, scrollState: scrollState, resetGeneration: scrollState.resetGeneration,
            typography: RecordCardTypography(
                title: Font.headline.resolve(in: fontContext), summary: Font.subheadline.resolve(in: fontContext),
                caption: Font.caption.resolve(in: fontContext), minimumHeight: minimumHeight, maximumHeight: maximumHeight),
            colorScheme: environment.colorScheme
        ) { note in
            // Copy only display settings. Copying the entire environment also
            // imports navigation accessibility state into these independent hosts.
            AnyView(
                card(note)
                    .id(note.id)
                    .environment(\.dynamicTypeSize, environment.dynamicTypeSize)
                    .environment(\.colorScheme, environment.colorScheme)
                    .environment(\.locale, environment.locale)
                    .environment(\.layoutDirection, environment.layoutDirection)
                    .tint(AppTheme.accent)
            )
        }
    }
}

@MainActor
final class RecordGalleryCoordinator: NSObject {
    let geometry: RecordGalleryLayout
    var notes: [Note] = []
    var card: (Note) -> AnyView = { _ in AnyView(EmptyView()) }
    var scrollState = RecordGalleryScrollState()
    var resetGeneration = -1
    private(set) var colorScheme: ColorScheme = .light
    private(set) var createdHostCount = 0

    init(geometry: RecordGalleryLayout) {
        self.geometry = geometry
        super.init()
    }

    func update(_ gallery: NativeRecordGallery) -> Bool {
        let needsInitialReload = notes.isEmpty && !gallery.notes.isEmpty
        card = gallery.card
        colorScheme = gallery.colorScheme
        scrollState = gallery.scrollState
        // Reuse previews across parent updates; don't project rich text again just
        // because a menu, selection or appearance changed.
        let old = Dictionary(uniqueKeysWithValues: zip(notes, geometry.previews).map { ($0.0.id, ($0.0, $0.1)) })
        let previews = gallery.notes.map { note in
            if let (previous, preview) = old[note.id], previous == note { return preview }
            return RecordCardPreview(note: note)
        }
        notes = gallery.notes
        let changed = geometry.update(previews: previews, typography: gallery.typography)
        return changed || needsInitialReload
    }

    func didCreateHost() { createdHostCount += 1 }
}

#if os(macOS)
    struct NativeRecordGallery: NSViewRepresentable {
        let notes: [Note]
        let scrollState: RecordGalleryScrollState
        let resetGeneration: Int
        let typography: RecordCardTypography
        var colorScheme: ColorScheme = .light
        let card: (Note) -> AnyView

        func makeCoordinator() -> RecordGalleryCoordinator { RecordGalleryCoordinator(geometry: scrollState.geometry) }

        func makeNSView(context: Context) -> RecordGalleryScrollView {
            makeScrollView(coordinator: context.coordinator)
        }

        func makeScrollView(coordinator: RecordGalleryCoordinator) -> RecordGalleryScrollView {
            let scroll = RecordGalleryScrollView()
            scroll.pendingOffset = scrollState.offset
            let collection = NSCollectionView()
            let layout = NativeRecordMasonryLayout()
            layout.geometry = coordinator.geometry
            collection.collectionViewLayout = layout
            collection.dataSource = coordinator
            collection.register(RecordGalleryItem.self, forItemWithIdentifier: .init("record-card"))
            collection.backgroundColors = [.clear]
            collection.autoresizingMask = [.width]
            collection.isSelectable = false
            scroll.hasVerticalScroller = true
            scroll.drawsBackground = false
            scroll.setAccessibilityIdentifier("record-gallery")
            let clip = RecordGalleryClipView()
            clip.drawsBackground = false
            clip.scrollState = scrollState
            scroll.contentView = clip
            scroll.documentView = collection
            return scroll
        }

        func updateNSView(_ scroll: RecordGalleryScrollView, context: Context) {
            update(scroll, coordinator: context.coordinator)
        }

        func update(_ scroll: RecordGalleryScrollView, coordinator: RecordGalleryCoordinator) {
            let changed = coordinator.update(self)
            guard let collection = scroll.documentView as? NSCollectionView else { return }
            if coordinator.resetGeneration != resetGeneration {
                coordinator.resetGeneration = resetGeneration
                scroll.pendingOffset = scrollState.offset
            }
            if changed {
                collection.collectionViewLayout?.invalidateLayout()
                collection.reloadData()
            } else {
                for item in collection.visibleItems() {
                    guard let path = collection.indexPath(for: item), notes.indices.contains(path.item),
                        let item = item as? RecordGalleryItem
                    else { continue }
                    item.setContent(card(notes[path.item]), colorScheme: colorScheme)
                }
            }
            scroll.needsLayout = true
        }
    }

    final class RecordGalleryClipView: NSClipView {
        var scrollState: RecordGalleryScrollState?
        override var isFlipped: Bool { true }

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self, selector: #selector(recordOffset), name: NSView.boundsDidChangeNotification, object: self)
        }

        required init?(coder: NSCoder) { nil }

        @objc private func recordOffset() {
            if window != nil, let scroll = enclosingScrollView as? RecordGalleryScrollView, scroll.pendingOffset == nil {
                scrollState?.offset = max(0, bounds.minY)
            }
        }
    }

    final class RecordGalleryScrollView: NSScrollView {
        var pendingOffset: CGFloat?

        override func layout() {
            super.layout()
            guard let collection = documentView as? NSCollectionView,
                contentSize.width > 0, contentSize.height > 0
            else { return }
            collection.frame.size.width = contentSize.width
            collection.layoutSubtreeIfNeeded()
            if let offset = pendingOffset {
                let height = collection.collectionViewLayout?.collectionViewContentSize.height ?? 0
                contentView.scroll(to: NSPoint(x: 0, y: min(offset, max(0, height - contentSize.height))))
                reflectScrolledClipView(contentView)
                pendingOffset = nil
            }
        }
    }

    final class RecordGalleryItem: NSCollectionViewItem {
        private var host: NSHostingView<AnyView>?
        var hasHost: Bool { host != nil }

        override func loadView() { view = NSView() }

        func setContent(_ content: AnyView, colorScheme: ColorScheme) {
            // Independent hosts need the AppKit appearance as well as SwiftUI's colorScheme:
            // native semantic backgrounds otherwise retain the previous window appearance.
            let appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
            view.appearance = appearance
            if let host {
                host.appearance = appearance
                host.rootView = content
                return
            }
            let host = NSHostingView(rootView: content)
            host.appearance = appearance
            host.sizingOptions = []
            host.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(host)
            NSLayoutConstraint.activate([
                host.leadingAnchor.constraint(equalTo: view.leadingAnchor), host.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                host.topAnchor.constraint(equalTo: view.topAnchor), host.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])
            self.host = host
        }

        override func prepareForReuse() {
            super.prepareForReuse()
            host?.rootView = AnyView(EmptyView())
        }
    }

    extension RecordGalleryCoordinator: NSCollectionViewDataSource {
        func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { notes.count }

        func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
            let item = collectionView.makeItem(withIdentifier: .init("record-card"), for: indexPath)
            if let item = item as? RecordGalleryItem {
                if !item.hasHost { didCreateHost() }
                item.setContent(card(notes[indexPath.item]), colorScheme: colorScheme)
            }
            return item
        }
    }

    final class NativeRecordMasonryLayout: NSCollectionViewLayout {
        var geometry = RecordGalleryLayout()

        override func prepare() {
            super.prepare()
            geometry.prepare(width: collectionView?.enclosingScrollView?.contentSize.width ?? 0, minimumColumnWidth: 220)
        }

        override var collectionViewContentSize: NSSize { geometry.index.contentSize }

        override func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool {
            newBounds.width != geometry.index.contentSize.width
        }

        override func layoutAttributesForElements(in rect: NSRect) -> [NSCollectionViewLayoutAttributes] {
            geometry.index.items(in: rect).compactMap { layoutAttributesForItem(at: IndexPath(item: $0, section: 0)) }
        }

        override func layoutAttributesForItem(at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
            guard geometry.index.frames.indices.contains(indexPath.item) else { return nil }
            let attributes = NSCollectionViewLayoutAttributes(forItemWith: indexPath)
            attributes.frame = geometry.index.frames[indexPath.item]
            return attributes
        }
    }
#else
    struct NativeRecordGallery: UIViewRepresentable {
        let notes: [Note]
        let scrollState: RecordGalleryScrollState
        let resetGeneration: Int
        let typography: RecordCardTypography
        var colorScheme: ColorScheme = .light
        let card: (Note) -> AnyView

        func makeCoordinator() -> RecordGalleryCoordinator { RecordGalleryCoordinator(geometry: scrollState.geometry) }

        func makeUIView(context: Context) -> RecordGalleryCollectionView {
            let layout = NativeRecordMasonryLayout()
            layout.geometry = context.coordinator.geometry
            let collection = RecordGalleryCollectionView(frame: .zero, collectionViewLayout: layout)
            collection.pendingOffset = scrollState.offset
            collection.backgroundColor = .clear
            collection.alwaysBounceVertical = true
            collection.dataSource = context.coordinator
            collection.delegate = context.coordinator
            collection.isPrefetchingEnabled = false
            collection.register(RecordGalleryCell.self, forCellWithReuseIdentifier: "record-card")
            collection.accessibilityIdentifier = "record-gallery"
            return collection
        }

        func updateUIView(_ collection: RecordGalleryCollectionView, context: Context) {
            let coordinator = context.coordinator
            let changed = coordinator.update(self)
            if coordinator.resetGeneration != resetGeneration {
                coordinator.resetGeneration = resetGeneration
                collection.pendingOffset = scrollState.offset
            }
            if changed {
                collection.collectionViewLayout.invalidateLayout()
                collection.reloadData()
            } else {
                for path in collection.indexPathsForVisibleItems {
                    guard notes.indices.contains(path.item), let cell = collection.cellForItem(at: path) else { continue }
                    cell.contentConfiguration = UIHostingConfiguration { card(notes[path.item]) }.margins(.all, 0)
                }
            }
            collection.setNeedsLayout()
        }
    }

    final class RecordGalleryCollectionView: UICollectionView {
        var pendingOffset: CGFloat?

        override func layoutSubviews() {
            super.layoutSubviews()
            guard bounds.width > 0, bounds.height > 0, let offset = pendingOffset else { return }
            let maximum = max(0, contentSize.height - bounds.height + adjustedContentInset.top + adjustedContentInset.bottom)
            setContentOffset(CGPoint(x: 0, y: min(offset, maximum) - adjustedContentInset.top), animated: false)
            pendingOffset = nil
        }
    }

    final class RecordGalleryCell: UICollectionViewCell {
        var hasHostedContent = false
        override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes)
            -> UICollectionViewLayoutAttributes
        {
            // The shared text geometry is authoritative; don't trigger full layout
            // invalidation from the hosting configuration's intrinsic size.
            layoutAttributes
        }
    }

    extension RecordGalleryCoordinator: UICollectionViewDataSource, UICollectionViewDelegate {
        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { notes.count }

        func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "record-card", for: indexPath)
            if let cell = cell as? RecordGalleryCell, !cell.hasHostedContent {
                didCreateHost()
                cell.hasHostedContent = true
            }
            let content = card(notes[indexPath.item])
            cell.contentConfiguration = UIHostingConfiguration { content }.margins(.all, 0)
            return cell
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard let collection = scrollView as? RecordGalleryCollectionView, collection.pendingOffset == nil else { return }
            scrollState.offset = max(0, scrollView.contentOffset.y + scrollView.adjustedContentInset.top)
        }
    }

    final class NativeRecordMasonryLayout: UICollectionViewLayout {
        var geometry = RecordGalleryLayout()

        override func prepare() {
            super.prepare()
            geometry.prepare(width: collectionView?.bounds.width ?? 0, minimumColumnWidth: 160)
        }

        override var collectionViewContentSize: CGSize { geometry.index.contentSize }

        override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
            newBounds.width != geometry.index.contentSize.width
        }

        override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
            geometry.index.items(in: rect).compactMap { layoutAttributesForItem(at: IndexPath(item: $0, section: 0)) }
        }

        override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
            guard geometry.index.frames.indices.contains(indexPath.item) else { return nil }
            let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
            attributes.frame = geometry.index.frames[indexPath.item]
            return attributes
        }
    }
#endif
