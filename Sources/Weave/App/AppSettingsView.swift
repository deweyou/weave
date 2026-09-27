import SwiftUI

struct AppSettingsView: View {
    @Environment(AppPreferences.self) private var preferences

    var body: some View {
        #if os(macOS)
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    Text("settings.title")
                        .font(.largeTitle.bold())
                        .padding(.bottom, 8)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("settings.basics").font(.title2.weight(.semibold))
                        GroupBox {
                            VStack(spacing: 0) {
                                HStack(spacing: 24) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("settings.theme")
                                        Text("settings.theme.description")
                                            .font(.callout).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                    themePicker.labelsHidden().fixedSize()
                                }
                                .padding(12)
                                Divider().padding(.horizontal, 12)
                                HStack(spacing: 24) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("settings.language")
                                        languageExplanation
                                            .font(.callout).foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    Spacer(minLength: 0)
                                    languagePicker.labelsHidden().fixedSize()
                                }
                                .padding(12)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(maxWidth: 720, alignment: .leading)
                .padding(.horizontal, 32)
                .padding(.vertical, 48)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .navigationTitle(L10n.string("settings.title"))
        #else
            Form {
                Section {
                    themePicker
                    languagePicker
                } header: {
                    Text("settings.basics")
                } footer: {
                    languageExplanation
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .navigationTitle(L10n.string("settings.title"))
        #endif
    }

    private var themePicker: some View {
        @Bindable var preferences = preferences
        return Picker("settings.theme", selection: $preferences.theme) {
            Text("settings.theme.light").tag(AppPreferences.Theme.light)
            Text("settings.theme.dark").tag(AppPreferences.Theme.dark)
            Text("settings.theme.system").tag(AppPreferences.Theme.system)
        }
        .accessibilityIdentifier("settings-theme")
        #if os(macOS)
            .pickerStyle(.menu)
            .tint(.primary)
            .pointerStyle(.link)
        #endif
    }

    private var languagePicker: some View {
        @Bindable var preferences = preferences
        return Picker("settings.language", selection: $preferences.language) {
            Text(verbatim: "中文").tag(AppPreferences.Language.chinese)
            Text(verbatim: "English").tag(AppPreferences.Language.english)
        }
        .accessibilityIdentifier("settings-language")
        #if os(macOS)
            .pickerStyle(.menu)
            .tint(.primary)
            .pointerStyle(.link)
        #endif
    }

    @ViewBuilder private var languageExplanation: some View {
        if preferences.language != preferences.activeLanguage {
            Text("settings.language.saved")
                .accessibilityIdentifier("settings-language-pending")
        } else {
            Text("settings.language.restart_required")
        }
    }
}
