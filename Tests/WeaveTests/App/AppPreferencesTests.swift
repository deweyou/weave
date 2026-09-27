import Foundation
import Testing

@testable import Weave

@MainActor
struct AppPreferencesTests {
    @Test func restoresChoicesWithoutChangingActiveLanguage() throws {
        let suite = "AppPreferencesTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferences(defaults: defaults, activeLanguage: .chinese)
        #expect(preferences.theme == .system)
        #expect(preferences.language == .chinese)

        preferences.theme = .dark
        preferences.language = .english
        #expect(preferences.activeLanguage == .chinese)
        #expect(defaults.stringArray(forKey: "AppleLanguages") == ["en"])

        let restored = AppPreferences(defaults: defaults, activeLanguage: .english)
        #expect(restored.theme == .dark)
        #expect(restored.language == .english)
        #expect(restored.activeLanguage == .english)
        restored.theme = .system
        #expect(AppPreferences(defaults: defaults, activeLanguage: .english).theme.colorScheme == nil)
    }

    @Test func invalidPreferencesFallBackWithoutTouchingOtherDefaults() throws {
        let suite = "AppPreferencesTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("invalid", forKey: "appearance.theme")
        defaults.set("invalid", forKey: "appearance.language")
        defaults.set("keep", forKey: "unrelated")
        let preferences = AppPreferences(defaults: defaults, activeLanguage: .english)
        #expect(preferences.theme == .system)
        #expect(preferences.language == .english)
        preferences.language = .chinese
        #expect(defaults.stringArray(forKey: "AppleLanguages") == ["zh-Hans"])
        #expect(defaults.string(forKey: "unrelated") == "keep")
    }

    @Test(arguments: AppPreferences.Language.allCases)
    func bundledTranslationsAndInterpolation(language: AppPreferences.Language) {
        #expect(L10n.bundle(for: language).bundleURL.lastPathComponent.lowercased() == "\(language.rawValue.lowercased()).lproj")
        #expect(L10n.string("设置", language: language) == (language == .chinese ? "设置" : "Settings"))
        let column = 3
        #expect(
            L10n.string("第 \(column) 列表头", language: language)
                == (language == .chinese ? "第 3 列表头" : "Column 3 Header"))
        let content = "中文 👋 title"
        #expect(
            L10n.string("将“\(content)”标记为已完成", language: language)
                == (language == .chinese ? "将“中文 👋 title”标记为已完成" : "Mark “中文 👋 title” as Complete"))
    }

    @Test(arguments: [0, 1, 2])
    func localizedCountsUseCorrectPlural(count: Int) {
        #expect(L10n.string("\(count) 条记录", language: .english) == "\(count) " + (count == 1 ? "note" : "notes"))
        #expect(L10n.string("\(count) 条记录", language: .chinese) == "\(count) 条记录")
        #expect(L10n.string("\(count) 字符", language: .english) == "\(count) " + (count == 1 ? "character" : "characters"))
    }

    @Test func translationCatalogsHaveMatchingKeysAndFormatArguments() throws {
        func catalog(_ language: AppPreferences.Language) throws -> [String: String] {
            let url = try #require(L10n.bundle(for: language).url(forResource: "Localizable", withExtension: "strings"))
            let value = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil)
            return try #require(value as? [String: String])
        }
        let chinese = try catalog(.chinese)
        let english = try catalog(.english)
        #expect(chinese.count > 150)
        #expect(Set(chinese.keys) == Set(english.keys))
        let placeholders = /%(?:\d+\$)?(?:lld|@)/
        for (key, value) in chinese {
            let translation = try #require(english[key])
            #expect(
                value.matches(of: placeholders).map { String($0.output) }
                    == translation.matches(of: placeholders).map { String($0.output) },
                "Mismatched placeholders for \(key)")
            #expect(!translation.isEmpty)
        }
    }
}
