import SwiftUI

/// Edits the lyrics offset — the media time at which the song begins. A typed
/// `M:SS.mmm` field plus a "Set from Playhead" button. Reused by the Lyrics
/// Editor sheet (and, in a later leaf, the lyric lane).
struct LyricsOffsetControl: View {

    /// The current offset.
    let offsetSeconds: TimeInterval
    /// The current playhead time, for "Set from Playhead".
    let playhead: () -> TimeInterval
    /// Commits a new offset (routes through `CueCommands.setLyricsOffset`).
    let onCommit: (TimeInterval) -> Void

    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text("Sync Offset")
                .foregroundStyle(.secondary)
            TextField("0:00.000", text: $text)
                .frame(width: 96)
                .focused($focused)
                .onSubmit(commitText)
                .onChange(of: focused) { _, isFocused in
                    if !isFocused { commitText() }
                }
                .accessibilityIdentifier("lyricsOffsetField")
            Button("Set from Playhead") { onCommit(playhead()) }
                .accessibilityIdentifier("lyricsOffsetSetFromPlayhead")
        }
        .onAppear { text = LyricsTimeFormat.string(offsetSeconds) }
        .onChange(of: offsetSeconds) { _, new in
            if !focused { text = LyricsTimeFormat.string(new) }
        }
    }

    /// Parses the field; reverts to the canonical string on bad input.
    private func commitText() {
        if let parsed = LyricsTimeFormat.parse(text) {
            onCommit(parsed)
        }
        text = LyricsTimeFormat.string(offsetSeconds)
    }
}
