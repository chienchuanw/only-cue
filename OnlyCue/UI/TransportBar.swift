import SwiftUI

struct TransportBar: View {

    let engine: PlayerEngine
    var cues: [Cue] = []
    var mediaDuration: TimeInterval = 0
    var timecodeSettings: ProjectTimecodeSettings = .default
    /// Active media item — drives the SMPTE readout's per-clip start TC.
    /// `nil` when no item is loaded, in which case the readout falls back to
    /// rendering `00:00:00:00` at the project framerate.
    var activeItem: MediaItem?

    /// LTC decoded off the active media file, if any (supplied via the
    /// environment by `StripedTimecodeHost`) — takes priority over
    /// `timecodeSettings` for the SMPTE readout.
    @Environment(\.stripedTimecode) private var stripedTimecode
    @ObservedObject private var ltcRoutingStore = LTCRoutingStore.shared

    @AppStorage("transport.countdownMode") private var countdownModeRaw: String = CountdownMode.time.rawValue

    private var countdownMode: CountdownMode {
        CountdownMode(rawValue: countdownModeRaw) ?? .time
    }

    private func cycleCountdownMode() {
        countdownModeRaw = (countdownMode == .time ? CountdownMode.beats : .time).rawValue
    }

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

    /// The bpm/beatsPerBar in effect at `currentTime` — taken from the most
    /// recent cue with `time ≤ currentTime` AND a non-nil `bpm`. Cues without
    /// `bpm` are skipped (a tempo-less cue does not "clear" prior tempo).
    /// `beatsPerBar` defaults to 4 when the cue has bpm but no explicit meter.
    /// Doesn't assume `cues` is time-sorted (mirrors `nextCueInterval`).
    static func activeBPM(currentTime: TimeInterval, cues: [Cue]) -> (bpm: Double, beatsPerBar: Int)? {
        let candidate = cues
            .filter { $0.time <= currentTime && $0.bpm != nil }
            .max(by: { $0.time < $1.time })
        guard let cue = candidate, let bpm = cue.bpm else { return nil }
        return (bpm: bpm, beatsPerBar: cue.beatsPerBar ?? 4)
    }

    /// Beat-mode display value. Two zones:
    /// - `.bars(n)` outside one bar (n ≥ 1, integer bars rounded down).
    /// - `.pulse(remaining: r)` inside one bar (r ∈ 1...beatsPerBar), drives the
    ///   per-beat "4 · 3 · 2 · 1" countdown.
    enum BeatCountdown: Equatable {
        case bars(Int)
        case pulse(remaining: Int)
    }

    /// Computes the beat-mode display value from a time interval and the active
    /// tempo. `beatsLeft = ceil(interval * bpm / 60)`. Pulse remaining is
    /// floored at 1 so the readout never blanks at the cue boundary.
    static func beatCountdown(interval: TimeInterval, bpm: Double, beatsPerBar: Int) -> BeatCountdown {
        let beatsLeft = Int(ceil(max(interval, 0) * bpm / 60.0))
        if beatsLeft > beatsPerBar {
            return .bars(beatsLeft / beatsPerBar)
        }
        return .pulse(remaining: max(1, beatsLeft))
    }

    /// User preference for the next-cue countdown format. Persisted app-wide
    /// via `@AppStorage("transport.countdownMode")`. A per-document preference
    /// would require a ProjectModel schema bump; not worth it for a display toggle.
    enum CountdownMode: String {
        case time
        case beats
    }

    /// Builds the countdown's display string. Pure — no view state, no engine.
    /// In `.beats` mode without `activeTempo`, falls back to the time format
    /// with a trailing `ⓘ` glyph so the user sees the mode is active but data
    /// is missing (the View attaches a tooltip explaining how to fix it).
    static func countdownLabel(
        mode: CountdownMode,
        interval: TimeInterval,
        activeTempo: (bpm: Double, beatsPerBar: Int)?
    ) -> String {
        let timeBody = TimeFormat.compactCountdown(interval)
        switch mode {
        case .time:
            return "Next: \(timeBody)"
        case .beats:
            guard let tempo = activeTempo else {
                return "Next: \(timeBody) ⓘ"
            }
            switch beatCountdown(interval: interval, bpm: tempo.bpm, beatsPerBar: tempo.beatsPerBar) {
            case .bars(let n):
                return "Next: ~\(n) bar\(n == 1 ? "" : "s")"
            case .pulse:
                let dots = (1...tempo.beatsPerBar)
                    .reversed()
                    .map(String.init)
                    .joined(separator: " · ")
                return "Next: \(dots)"
            }
        }
    }

    /// The SMPTE timecode at the playhead — the active file's striped LTC when
    /// it has any, otherwise derived from the project settings + active item's
    /// `startTimecodeFrames` (or `00:00:00:00` when no item is loaded).
    private var smpteReadout: String {
        if let striped = stripedTimecode {
            return striped.timecode(atPlaybackSeconds: engine.currentTime).displayString
        }
        guard let activeItem else {
            return Timecode(frameCount: 0, rate: timecodeSettings.framerate).displayString
        }
        return timecodeSettings.timecode(atPlaybackSeconds: engine.currentTime, forItem: activeItem).displayString
    }

    private var smpteReadoutHelp: String {
        if stripedTimecode != nil {
            return "SMPTE timecode read from the media file's LTC track."
        }
        return "SMPTE timecode at the playhead (\(timecodeSettings.framerate.displayName); edit in Tools → Timecode Settings…)."
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(timeReadout)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("currentTimeReadout")

            if ltcRoutingStore.settings.isEnabled {
                Text("SMPTE \(smpteReadout)")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("smpteTimecode")
                    .help(smpteReadoutHelp)
            }

            if let interval = Self.nextCueInterval(currentTime: engine.currentTime, cues: cues) {
                let tempo = Self.activeBPM(currentTime: engine.currentTime, cues: cues)
                let label = Self.countdownLabel(
                    mode: countdownMode,
                    interval: interval,
                    activeTempo: tempo
                )
                Button(action: cycleCountdownMode) {
                    Text(label)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("nextCueCountdown")
                }
                .buttonStyle(.plain)
                .help(countdownMode == .beats && tempo == nil
                      ? "Set a tempo on a cue to enable beat countdown. Click to switch back to time."
                      : "Click to switch between time and beat countdown.")
                .accessibilityIdentifier("nextCueCountdownToggle")
            }

        }
    }
}
