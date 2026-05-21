import SwiftUI

/// The keyboard-shortcut reference, shown from the empty state's `?` button.
/// Replaces the always-on cheat-sheet that used to sit permanently in the
/// empty document. Reads the *current* keymap so hints stay accurate after
/// rebinding in Settings → Keyboard.
struct ShortcutReferencePopover: View {

    @ObservedObject private var keymapStore = KeymapStore.shared

    private func chord(_ action: KeymapAction) -> String {
        keymapStore.keymap.chord(for: action).displayString
    }

    private var rows: [(label: String, chord: String)] {
        [
            (label: "Import media", chord: chord(.importMedia)),
            (label: "Add cue at playhead", chord: chord(.addCue)),
            (label: "Step to previous / next cue",
             chord: "\(chord(.stepPrevCue))  \(chord(.stepNextCue))"),
            (label: "Toggle notes overlay", chord: chord(.toggleNotesOverlay)),
            (label: "Pause at each cue", chord: chord(.togglePauseAtEachCue))
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            Text("Keyboard Shortcuts").dsSectionHeader()
            ForEach(rows, id: \.label) { row in
                HStack {
                    Text(row.label)
                        .font(DS.Text.body)
                        .foregroundStyle(DS.Color.textSecondary)
                    Spacer(minLength: DS.Space.lg)
                    Text(row.chord)
                        .font(DS.Text.monoSmall)
                        .foregroundStyle(DS.Color.textPrimary)
                }
            }
        }
        .padding(DS.Space.lg)
        .frame(width: 280)
        .accessibilityIdentifier("shortcutReferenceList")
    }
}
