import SwiftUI

/// Shown in the main pane when no media item is active — a single calm import
/// well. The disabled transport, cue UI, and shortcut cheat-sheet that used to
/// stack here are gone; they appear only once media exists (ADR-024).
struct DocumentEmptyState: View {

    let onImport: () -> Void
    @State private var showShortcuts = false

    var body: some View {
        VStack(spacing: DS.Space.md) {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 30)) // off-grid: empty-state glyph size
                .foregroundStyle(DS.Color.textTertiary)
            Text("No media imported")
                .font(DS.Text.heading)
                .foregroundStyle(DS.Color.textPrimary)
            Text("Drag an audio or video file here")
                .font(DS.Text.body)
                .foregroundStyle(DS.Color.textSecondary)
            Button("Import Media…") { onImport() }
                .accessibilityIdentifier("importMediaButton")
                .help("Import Media (⌘O)")
                .padding(.top, DS.Space.xs)
            Text("or press ⌘O")
                .font(DS.Text.label)
                .foregroundStyle(DS.Color.textTertiary)
        }
        .dsImportWell()
        .overlay(alignment: .topTrailing) { shortcutButton }
        // `.contain` keeps the well queryable AND lets XCUITest reach the
        // Import button and the shortcut button beneath the container id.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("documentImportWell")
    }

    private var shortcutButton: some View {
        Button { showShortcuts.toggle() } label: {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 14)) // off-grid: control glyph size
                .foregroundStyle(DS.Color.textTertiary)
        }
        .buttonStyle(.plain)
        .padding(DS.Space.md)
        .help("Keyboard shortcuts")
        .accessibilityIdentifier("shortcutReferenceButton")
        .popover(isPresented: $showShortcuts) { ShortcutReferencePopover() }
    }
}
