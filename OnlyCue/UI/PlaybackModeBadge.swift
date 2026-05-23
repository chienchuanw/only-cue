import SwiftUI

/// TransportControls indicator for non-default playback modes. Hidden when
/// `mode == .playOnce` so the bar stays clean in the most common state. The
/// `accessibilityValue` is the raw `PlaybackMode.rawValue` so UI tests can
/// assert on it without parsing glyphs.
struct PlaybackModeBadge: View {

    let mode: PlaybackMode

    var body: some View {
        Group {
            switch mode {
            case .playOnce:
                EmptyView()
            case .loop:
                Image(systemName: "repeat")
                    .help("Looping current media")
            case .autoNext:
                Image(systemName: "forward.end")
                    .help("Auto-advancing to next media")
            }
        }
        .imageScale(.medium)
        .foregroundStyle(DS.Color.textSecondary)
        .accessibilityIdentifier("playbackModeBadge")
        .accessibilityValue(mode.rawValue)
    }
}
