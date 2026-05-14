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
