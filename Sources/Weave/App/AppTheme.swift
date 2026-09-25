import SwiftUI

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

/// Shared display palette. A future appearance setting can choose the accent here;
/// theme colors never become persisted document attributes.
enum AppTheme {
    static var accent: Color { Color(nativeAccent) }

    #if os(macOS)
        static var nativeAccent: NSColor { .systemBlue }
    #else
        static var nativeAccent: UIColor { .systemBlue }
    #endif
}
