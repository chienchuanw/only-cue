import SwiftUI

/// Settings → General pane: the in-app language picker. Restart-to-apply — the
/// choice is persisted immediately (via `LanguagePreference`), but macOS only
/// re-reads `AppleLanguages` at launch, so an alert offers to relaunch now.
/// zh-Hant localization, Phase 2.
struct GeneralSettingsView: View {

    @State private var selection = LanguagePreference.current()
    @State private var showingRelaunchAlert = false

    var body: some View {
        Form {
            Section {
                Picker("Language", selection: $selection) {
                    ForEach(AppLanguage.allCases) { language in
                        label(for: language).tag(language)
                    }
                }
                .accessibilityIdentifier("languagePicker")
                .onChange(of: selection) { _, newValue in
                    LanguagePreference.set(newValue)
                    showingRelaunchAlert = true
                }
            } footer: {
                Text("Changing the language takes effect after OnlyCue restarts.")
                    .font(.caption)
                    .foregroundStyle(DS.Color.textSecondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 600, height: 360)
        .accessibilityIdentifier("generalSettings")
        .alert("Relaunch to apply?", isPresented: $showingRelaunchAlert) {
            Button("Relaunch") { AppRelauncher.relaunch() }
            Button("Later", role: .cancel) {}
        } message: {
            Text("The new language takes effect after OnlyCue restarts.")
        }
    }

    /// "System" is localized; language names are endonyms shown in their own
    /// script and never localized.
    private func label(for language: AppLanguage) -> Text {
        switch language {
        case .system: return Text("System")
        case .english: return Text(verbatim: "English")
        case .traditionalChinese: return Text(verbatim: "繁體中文")
        }
    }
}
