import SwiftUI

/// Edits the lyrics sync offset — the media time at which the song begins.
/// Displays and parses as SMPTE `HH:MM:SS:FF` at the project framerate (Figma
/// `318:1473`, ADR-028), in a boxed field, plus a "Set from Playhead" button.
/// `Timecode` clamps negatives to zero, so the offset stays ≥ 0.
struct LyricsOffsetControl: View {

    /// The current offset.
    let offsetSeconds: TimeInterval
    /// The current playhead time, for "Set from Playhead".
    let playhead: () -> TimeInterval
    /// Commits a new offset (routes through `CueCommands.setLyricsOffset`).
    let onCommit: (TimeInterval) -> Void

    @Environment(\.projectFramerate) private var framerate
    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: DS.Space.sm) {
            Text("Sync Offset")
                .foregroundStyle(.secondary)
            Spacer(minLength: DS.Space.sm)
            Button("Set from Playhead") { onCommit(max(0, playhead())) }
                .accessibilityIdentifier("lyricsOffsetSetFromPlayhead")
            offsetField
        }
        .onAppear { text = formatted(offsetSeconds) }
        .onChange(of: offsetSeconds) { _, new in if !focused { text = formatted(new) } }
        .onChange(of: framerate) { _, _ in if !focused { text = formatted(offsetSeconds) } }
    }

    private var offsetField: some View {
        TextField("HH:MM:SS:FF", text: $text)
            .textFieldStyle(.plain)
            .font(DS.Text.mono)
            .multilineTextAlignment(.center)
            .frame(width: 120)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.sm)
                    .fill(DS.Color.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.sm)
                    .strokeBorder(DS.Color.borderStrong, lineWidth: 1)
            )
            .focused($focused)
            .onSubmit(commitText)
            .onChange(of: focused) { _, isFocused in if !isFocused { commitText() } }
            .accessibilityIdentifier("lyricsOffsetField")
    }

    private func formatted(_ seconds: TimeInterval) -> String {
        TimeFormat.smpte(seconds, rate: framerate)
    }

    /// Parses the SMPTE field; reverts to the canonical string on bad input.
    private func commitText() {
        if let parsed = Timecode.parse(text, rate: framerate) {
            onCommit(parsed.totalSeconds)
        }
        text = formatted(offsetSeconds)
    }
}
