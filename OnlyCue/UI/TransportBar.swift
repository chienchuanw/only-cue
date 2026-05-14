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
    @AppStorage("pauseAtEachCue") private var pauseAtEachCue = false
    @ObservedObject private var ltcRoutingStore = LTCRoutingStore.shared

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

    /// Mirror of `nextCueInterval`: time elapsed since the most recent cue at
    /// `time <= currentTime`. Inclusive `<=` so a cue exactly at `currentTime`
    /// reads as "Last: 0.0s" (operator just hit it). Returns nil when no past
    /// cue exists. Like the forward helper, doesn't assume sortedness — `max()`
    /// picks the most recent regardless of input order.
    static func lastCueElapsed(currentTime: TimeInterval, cues: [Cue]) -> TimeInterval? {
        cues
            .map(\.time)
            .filter { $0 <= currentTime }
            .max()
            .map { currentTime - $0 }
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
            Button {
                engine.toggle()
            } label: {
                Image(systemName: engine.rate > 0 ? "pause.fill" : "play.fill")
                    .frame(width: 16, height: 16)
            }
            .accessibilityIdentifier("playPauseButton")
            .accessibilityLabel(engine.rate > 0 ? "Pause" : "Play")
            .help("Play / Pause (Space)")

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

            if let interval = Self.lastCueElapsed(currentTime: engine.currentTime, cues: cues) {
                Text("Last: \(TimeFormat.compactCountdown(interval))")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("lastCueElapsed")
            }

            if let interval = Self.nextCueInterval(currentTime: engine.currentTime, cues: cues) {
                Text("Next: \(TimeFormat.compactCountdown(interval))")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("nextCueCountdown")
            }

            if pauseAtEachCue {
                HStack(spacing: 4) {
                    Image(systemName: "pause.circle")
                    Text("Pause: each cue")
                }
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("pauseAtEachCueIndicator")
                .help("Toggle with ⇧⌘P")
            }
        }
    }
}
