#if os(macOS)
    import AppKit
    import SwiftUI

    /// A non-intercepting native cursor region for controls layered over NSTextView.
    struct PointingHandRegion: NSViewRepresentable {
        func makeNSView(context: Context) -> PointingHandRegionView { PointingHandRegionView() }
        func updateNSView(_ view: PointingHandRegionView, context: Context) {
            view.window?.invalidateCursorRects(for: view)
        }
    }

    final class PointingHandRegionView: NSView {
        private static let regions = NSHashTable<PointingHandRegionView>.weakObjects()
        private var cursorTracking: NSTrackingArea?

        static func contains(_ point: NSPoint, in window: NSWindow?) -> Bool {
            guard let window else { return false }
            return regions.allObjects.contains {
                $0.window === window && !$0.isHiddenOrHasHiddenAncestor
                    && $0.visibleRect.contains($0.convert(point, from: nil))
            }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil {
                Self.regions.add(self)
            } else {
                Self.regions.remove(self)
            }
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func resetCursorRects() {
            super.resetCursorRects()
            addCursorRect(visibleRect, cursor: .pointingHand)
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let cursorTracking { removeTrackingArea(cursorTracking) }
            let area = NSTrackingArea(
                rect: .zero, options: [.cursorUpdate, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                owner: self, userInfo: nil)
            addTrackingArea(area)
            cursorTracking = area
        }

        override func cursorUpdate(with event: NSEvent) { NSCursor.pointingHand.set() }
        override func mouseEntered(with event: NSEvent) { NSCursor.pointingHand.set() }
        override func mouseExited(with event: NSEvent) { NSCursor.arrow.set() }
    }
#endif
