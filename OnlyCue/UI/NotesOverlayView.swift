import SwiftUI

/// Toggleable HUD-style overlay rendering the active cue's notes on top of the preview pane.
/// Show callers read this during run-throughs. Renders nothing when there's no active cue
/// or when the active cue's notes are empty — the toggle stays on but the layer disappears
/// rather than showing an empty card / placeholder text.
///
/// Appearance is driven entirely by `prefs` (`NotesOverlayPreferences`). When `prefs == .default`
/// the rendering visually matches the original PR #72 baseline: white `.title`-sized text on
/// `.ultraThinMaterial`, no cue-ID prefix.
///
/// Note on Dynamic Type: this overlay deliberately uses a fixed-point font size
/// (`28 * fontScale`) rather than the `.title` semantic style. The customisation sheet's
/// "Font Scale" slider (0.75×–3×) is the user-facing size knob; layering `.scaleEffect`
/// over a Dynamic-Type-aware style would make the slider's "1.50×" label lie about the
/// rendered size. Users who need larger text should raise the Font Scale slider rather
/// than rely on macOS's system text-size preference.
struct NotesOverlayView: View {

    let activeCue: Cue?
    var prefs: NotesOverlayPreferences = .default
    var cueNumberLabel: String?

    var body: some View {
        if let cue = activeCue, !cue.notes.isEmpty {
            Text(displayText(for: cue))
                .font(.system(size: 28 * prefs.fontScale, weight: .semibold))
                .foregroundStyle(textColor)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: 600)
                .background(background)
                .accessibilityIdentifier("notesOverlay")
        }
    }

    private func displayText(for cue: Cue) -> String {
        guard prefs.showCueIDPrefix, let label = cueNumberLabel else { return cue.notes }
        return "[\(label)] \(cue.notes)"
    }

    private var textColor: Color {
        Color(hex: prefs.textColorHex) ?? .primary
    }

    @ViewBuilder
    private var background: some View {
        if let hex = prefs.backgroundColorHex, let color = Color(hex: hex) {
            RoundedRectangle(cornerRadius: 12).fill(color)
        } else {
            RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial)
        }
    }
}
