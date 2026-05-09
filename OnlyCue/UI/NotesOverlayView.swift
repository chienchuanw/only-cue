import SwiftUI

/// Toggleable HUD-style overlay rendering the active cue's notes on top of the preview pane.
/// Show callers read this during run-throughs. Renders nothing when there's no active cue
/// or when the active cue's notes are empty — the toggle stays on but the layer disappears
/// rather than showing an empty card / placeholder text.
struct NotesOverlayView: View {

    let activeCue: Cue?

    var body: some View {
        if let cue = activeCue, !cue.notes.isEmpty {
            Text(cue.notes)
                .font(.title)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: 600)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier("notesOverlay")
        }
    }
}
