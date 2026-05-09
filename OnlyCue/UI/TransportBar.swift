import SwiftUI

struct TransportBar: View {

    let engine: PlayerEngine
    var cues: [Cue] = []

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

            Text(TimeFormat.hms(engine.currentTime))
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("currentTimeReadout")

            if let interval = Self.nextCueInterval(currentTime: engine.currentTime, cues: cues) {
                Text("Next: \(TimeFormat.compactCountdown(interval))")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("nextCueCountdown")
            }
        }
    }
}
