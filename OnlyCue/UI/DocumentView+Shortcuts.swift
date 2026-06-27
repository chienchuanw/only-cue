import SwiftUI

/// Invisible keyboard-shortcut hosts for `DocumentView`. Split into their own
/// file so the main `DocumentView` body stays under the SwiftLint
/// `file_length` cap. These render nothing (0×0, opacity 0) — they exist only
/// to register window-level keyboard shortcuts, and are mounted via the main
/// view's `.background` so they never affect layout.
extension DocumentView {

    var transportShortcuts: some View {
        ZStack {
            Button("Play/Pause") { engine.toggle() }
                .keyboardShortcut(shortcut(.playPause))
            Button("Back 1s") { jump(by: -1) }
                .keyboardShortcut(shortcut(.jumpBack))
            Button("Forward 1s") { jump(by: 1) }
                .keyboardShortcut(shortcut(.jumpForward))
            Button("Add Cue") { addCueAtPlayhead() }
                .keyboardShortcut(shortcut(.addCue))
                // No media, or Show mode is read-only — no cue creation (#592).
                .disabled(!canCreateCue)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
        // While an inline cue field is being edited, the bare left/right arrows
        // (jumpBack/jumpForward) must move the text caret, not seek (#573).
        .disabled(isEditingCueField)
    }

    var digitShortcuts: some View {
        ZStack {
            ForEach(0...9, id: \.self) { digit in
                Button("Cue Type \(digit)") { triggerHotkey(digit) }
                    .keyboardShortcut(shortcut(KeymapAction.addCueOfType(digit) ?? .addCueOfType0))
            }
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
        // Digit add-cue-of-type: no media, or Show mode is read-only (#592).
        .disabled(!canCreateCue)
    }
}
