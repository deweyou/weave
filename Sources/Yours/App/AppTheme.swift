import SwiftUI

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

/// Shared display palette. A future appearance setting can choose the accent here;
/// theme colors never become persisted document attributes.
enum AppTheme {
    #if os(macOS)
        typealias NativeColor = NSColor
    #else
        typealias NativeColor = UIColor
    #endif

    static let documentBody = documentColor(lightWhite: 0x33 / 255.0, name: "YoursDocumentBody")
    static let documentHeading = documentColor(lightWhite: 0x24 / 255.0, name: "YoursDocumentHeading")

    static func documentText(for role: String) -> NativeColor {
        role.hasPrefix("heading:") ? documentHeading : documentBody
    }

    static func isDefaultDocumentColor(_ color: NativeColor) -> Bool {
        #if os(macOS)
            color == .textColor || color == documentBody || color == documentHeading
        #else
            color == .label || color == documentBody || color == documentHeading
        #endif
    }

    private static func documentColor(lightWhite: CGFloat, name: String) -> NativeColor {
        #if os(macOS)
            NSColor(name: NSColor.Name(name)) { appearance in
                resolvedDocumentColor(
                    lightWhite: lightWhite, appearance: appearance,
                    increasedContrast: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast)
            }
        #else
            UIColor { traits in
                traits.userInterfaceStyle == .dark || traits.accessibilityContrast == .high
                    ? .label : UIColor(red: lightWhite, green: lightWhite, blue: lightWhite, alpha: 1)
            }
        #endif
    }

    #if os(macOS)
        static func resolvedDocumentColor(lightWhite: CGFloat, appearance: NSAppearance, increasedContrast: Bool) -> NSColor {
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return dark || increasedContrast ? .textColor : NSColor(srgbRed: lightWhite, green: lightWhite, blue: lightWhite, alpha: 1)
        }
    #endif

    static var accent: Color { Color(nativeAccent) }

    #if os(macOS)
        static var nativeAccent: NSColor { .systemBlue }
    #else
        static var nativeAccent: UIColor { .systemBlue }
    #endif
}
