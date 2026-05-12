import SwiftUI

/// Caption-style cheatsheet rendered in the empty-document footer.
/// Lists the shortcuts a new user is least likely to discover from menus
/// alone (add a cue, step cues, the notes overlay, pause-at-each-cue) — using
/// the *current* keymap so the hints stay accurate after rebinding in
/// Settings → Keyboard. Extracted from `DocumentView` to keep that struct
/// under SwiftLint's `type_body_length` cap.
struct DocumentShortcutHints: View {

    @ObservedObject private var keymapStore = KeymapStore.shared

    private func chord(_ action: KeymapAction) -> String {
        keymapStore.keymap.chord(for: action).displayString
    }

    var body: some View {
        VStack(spacing: 2) {
            Text("Drop files on the sidebar or press \(chord(.importMedia)) to import.")
            Text("\(chord(.addCue)) — add cue at playhead   •   \(chord(.stepPrevCue)) \(chord(.stepNextCue)) — step cues")
            Text("\(chord(.toggleNotesOverlay)) — notes overlay   •   \(chord(.togglePauseAtEachCue)) — pause at each cue")
        }
        .font(.system(.caption, design: .monospaced))
        .multilineTextAlignment(.center)
        .foregroundStyle(.tertiary)
        .padding(.top, 4)
        .accessibilityIdentifier("documentShortcutHints")
    }
}
