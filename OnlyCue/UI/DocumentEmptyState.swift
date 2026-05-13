import SwiftUI

/// Shown in the main pane when no media item is active. Carries the onboarding
/// affordances that used to sit permanently in the loaded pane: the Import
/// button and the keyboard-shortcut cheatsheet.
struct DocumentEmptyState: View {

    let onImport: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("No media imported")
                .font(.title3)
                .foregroundStyle(.secondary)
            Button("Import Media…") { onImport() }
                .accessibilityIdentifier("importMediaButton")
                .help("Import Media (⌘O)")
            DocumentShortcutHints()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
