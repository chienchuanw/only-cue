import SwiftUI

struct TransportBar: View {

    let engine: PlayerEngine
    var cues: [Cue] = []
    var mediaDuration: TimeInterval = 0

    @AppStorage("pauseAtEachCue") private var pauseAtEachCue = false

    /// Single-Text readout so the slash kerns correctly with monospaced digits and
    /// stays aligned on resize. When `mediaDuration` is 0 (no active item) the slash
    /// and total are omitted — `"00:00:00.000 / 00:00:00.000"` would be misleading.
    private var timeReadout: String {
        let current = TimeFormat.hms(engine.currentTime)
        guard mediaDuration > 0 else { return current }
        return "\(current) / \(TimeFormat.hms(mediaDuration))"
    }

    /// Strictly-greater filter: a cue exactly at `currentTime` is "now," not "next."
    /// Returns nil when no future cue exists (past last cue, or empty list).
    /// Doesn't assume `cues` is time-sorted (it is in practice, but the helper
    /// shouldn't depend on that — `min()` over the post-filter set picks the
    /// nearest regardless of input order).
    static func nextCueInterval(currentTime: TimeInterval, cues: [Cue]) -> TimeInterval? {
        cues
            .map(\.time)
            .filter { $0 > currentTime }
            .min()
            .map { $0 - currentTime }
    }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                engine.toggle()
            } label: {
                Image(systemName: engine.rate > 0 ? "pause.fill" : "play.fill")
                    .frame(width: 16, height: 16)
            }
            .accessibilityIdentifier("playPauseButton")
            .accessibilityLabel(engine.rate > 0 ? "Pause" : "Play")

            Text(timeReadout)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("currentTimeReadout")

            if let interval = Self.nextCueInterval(currentTime: engine.currentTime, cues: cues) {
                Text("Next: \(TimeFormat.compactCountdown(interval))")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("nextCueCountdown")
            }

            if pauseAtEachCue {
                Text("Pause: each cue")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("pauseAtEachCueIndicator")
            }
        }
    }
}
