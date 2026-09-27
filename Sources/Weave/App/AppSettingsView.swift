import SwiftUI

struct AppSettingsView: View {
    @Environment(AppPreferences.self) private var preferences

    var body: some View {
        #if os(macOS)
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    Text("设置")
                        .font(.largeTitle.bold())
                        .padding(.bottom, 8)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("基础").font(.title2.weight(.semibold))
                        GroupBox {
                            VStack(spacing: 0) {
                                HStack(spacing: 24) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("主题")
                                        Text("主题立即生效，不改变文档内容。")
                                            .font(.callout).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                    themePicker.labelsHidden().fixedSize()
                                }
                                .padding(12)
                                Divider().padding(.horizontal, 12)
                                HStack(spacing: 24) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("语言")
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
            .navigationTitle(L10n.string("设置"))
        #else
            Form {
                Section {
                    themePicker
                    languagePicker
                } header: {
                    Text("基础")
                } footer: {
                    languageExplanation
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .navigationTitle(L10n.string("设置"))
        #endif
    }

    private var themePicker: some View {
        @Bindable var preferences = preferences
        return Picker("主题", selection: $preferences.theme) {
            Text("浅色").tag(AppPreferences.Theme.light)
            Text("深色").tag(AppPreferences.Theme.dark)
            Text("跟随系统").tag(AppPreferences.Theme.system)
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
        return Picker("语言", selection: $preferences.language) {
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
            Text("语言已保存，下次启动 Weave 时生效。")
                .accessibilityIdentifier("settings-language-pending")
        } else {
            Text("语言更改将在下次启动时生效，包括应用菜单。")
        }
    }
}
