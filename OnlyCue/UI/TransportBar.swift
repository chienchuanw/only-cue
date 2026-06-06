import Foundation

/// Pure helpers for the transport's next-cue countdown and tempo display,
/// reused by `TransportControls`. Formerly a `View`; the Quiet Pro redesign
/// (ADR-024) moved all rendering to `TransportControls` and left this as a
/// namespace for the countdown / tempo math (still unit-tested directly).
enum TransportBar {

    /// Strictly-greater filter: a cue exactly at `currentTime` is "now," not "next."
    /// Returns nil when no future cue exists (past last cue, or empty list).
    /// Doesn't assume `cues` is time-sorted — `min()` picks the nearest.
    static func nextCueInterval(currentTime: TimeInterval, cues: [Cue]) -> TimeInterval? {
        cues
            .map(\.time)
            .filter { $0 > currentTime }
            .min()
            .map { $0 - currentTime }
    }

    /// The bpm/beatsPerBar in effect at `currentTime` — taken from the most
    /// recent cue with `time ≤ currentTime` AND a non-nil `bpm`. Cues without
    /// `bpm` are skipped. `beatsPerBar` defaults to 4 when the cue has bpm but
    /// no explicit meter. Doesn't assume `cues` is time-sorted.
    static func activeBPM(currentTime: TimeInterval, cues: [Cue]) -> (bpm: Double, beatsPerBar: Int)? {
        let candidate = cues
            .filter { $0.time <= currentTime && $0.bpm != nil }
            .max(by: { $0.time < $1.time })
        guard let cue = candidate, let bpm = cue.bpm else { return nil }
        return (bpm: bpm, beatsPerBar: cue.beatsPerBar ?? 4)
    }

    /// Beat-mode display value. `.bars(n)` outside one bar; `.pulse(remaining:)`
    /// inside one bar, driving the per-beat "4 · 3 · 2 · 1" countdown.
    enum BeatCountdown: Equatable {
        case bars(Int)
        case pulse(remaining: Int)
    }

    /// `beatsLeft = ceil(interval * bpm / 60)`. Pulse remaining is floored at 1
    /// so the readout never blanks at the cue boundary.
    static func beatCountdown(interval: TimeInterval, bpm: Double, beatsPerBar: Int) -> BeatCountdown {
        let beatsLeft = Int(ceil(max(interval, 0) * bpm / 60.0))
        if beatsLeft > beatsPerBar {
            return .bars(beatsLeft / beatsPerBar)
        }
        return .pulse(remaining: max(1, beatsLeft))
    }

    /// User preference for the next-cue countdown format. Persisted app-wide
    /// via `@AppStorage("transport.countdownMode")`.
    enum CountdownMode: String {
        case time
        case beats
    }

    /// Builds the countdown's display string. Pure — no view state, no engine.
    /// In `.beats` mode without `activeTempo`, falls back to the time format
    /// with a trailing `ⓘ` glyph so the user sees the mode is active but data
    /// is missing.
    static func countdownLabel(
        mode: CountdownMode,
        interval: TimeInterval,
        activeTempo: (bpm: Double, beatsPerBar: Int)?,
        rate: SMPTEFramerate
    ) -> String {
        // No "Next:" prefix — the zone's "NEXT CUE" caps header already names
        // it; the value stands alone (Figma 318:1310).
        let timeBody = TimeFormat.smpteCountdown(interval, rate: rate)
        switch mode {
        case .time:
            return timeBody
        case .beats:
            guard let tempo = activeTempo else {
                return "\(timeBody) ⓘ"
            }
            switch beatCountdown(interval: interval, bpm: tempo.bpm, beatsPerBar: tempo.beatsPerBar) {
            case .bars(let bars):
                return "~\(bars) bar\(bars == 1 ? "" : "s")"
            case .pulse:
                return (1...tempo.beatsPerBar)
                    .reversed()
                    .map(String.init)
                    .joined(separator: " · ")
            }
        }
    }
}
