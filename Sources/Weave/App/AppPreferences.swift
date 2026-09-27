import SwiftUI

/// Preferences are independent of note storage and isolated for each UI-test session.
@Observable @MainActor
final class AppPreferences {
    enum Theme: String, CaseIterable {
        case system, light, dark

        var colorScheme: ColorScheme? {
            switch self {
            case .system: nil
            case .light: .light
            case .dark: .dark
            }
        }
    }

    enum Language: String, CaseIterable, Sendable {
        case chinese = "zh-Hans"
        case english = "en"

        var locale: Locale { Locale(identifier: rawValue) }
    }

    private let defaults: UserDefaults
    let activeLanguage: Language
    var theme: Theme {
        didSet { defaults.set(theme.rawValue, forKey: "appearance.theme") }
    }
    var language: Language {
        didSet {
            defaults.set(language.rawValue, forKey: "appearance.language")
            // App-scoped only. Native system menus adopt this on the next launch.
            defaults.set([language.rawValue], forKey: "AppleLanguages")
        }
    }

    init(defaults: UserDefaults = PreferenceStorage.defaults, activeLanguage: Language = L10n.language) {
        self.defaults = defaults
        self.activeLanguage = activeLanguage
        theme = Theme(rawValue: defaults.string(forKey: "appearance.theme") ?? "") ?? .system
        language = Language(rawValue: defaults.string(forKey: "appearance.language") ?? "") ?? activeLanguage
    }
}

enum PreferenceStorage {
    static var defaults: UserDefaults {
        #if DEBUG
            if let value = ProcessInfo.processInfo.environment["WEAVE_UI_TEST_SESSION"],
                let session = UUID(uuidString: value),
                let defaults = UserDefaults(suiteName: "WeaveUITests.\(session.uuidString).preferences")
            {
                return defaults
            }
        #endif
        return .standard
    }
}

/// The active language is frozen for the process lifetime so changing it never rebuilds an editor.
enum L10n {
    static let language: AppPreferences.Language = {
        if let saved = PreferenceStorage.defaults.string(forKey: "appearance.language"),
            let language = AppPreferences.Language(rawValue: saved)
        {
            return language
        }
        return Locale.preferredLanguages.first?.hasPrefix("zh") == false ? .english : .chinese
    }()

    static let resources: Bundle = {
        #if SWIFT_PACKAGE
            Bundle.module
        #else
            Bundle.main
        #endif
    }()

    static func bundle(for language: AppPreferences.Language) -> Bundle {
        guard let path = resources.path(forResource: language.rawValue, ofType: "lproj"),
            let bundle = Bundle(path: path)
        else { return resources }
        return bundle
    }

    static func string(_ value: String.LocalizationValue, language: AppPreferences.Language = language) -> String {
        String(localized: value, bundle: bundle(for: language), locale: language.locale)
    }
}
