import SwiftUI

/// The B+ transport: a zoned bar of playback controls, the timecode readout
/// (with playback-rate badge and the LTC-gated SMPTE readout), and the
/// next-cue countdown, separated by hairline dividers. There is no progress
/// scrubber — the waveform timeline above is the single seek surface.
struct TransportControls: View {

    let engine: PlayerEngine
    var cues: [Cue] = []
    var mediaDuration: TimeInterval = 0
    var timecodeSettings: ProjectTimecodeSettings = .default
    /// Active media item — drives the SMPTE readout's per-clip start TC.
    var activeItem: MediaItem?
    /// Current end-of-media policy from the active document. Renders the
    /// non-default mode badge next to the playback-rate badge.
    var playbackMode: PlaybackMode = .playOnce
    /// Steps the playhead to the previous / next cue. Supplied by `DocumentView`.
    var onStepPrevCue: () -> Void = {}
    var onStepNextCue: () -> Void = {}

    @Environment(\.stripedTimecode) private var stripedTimecode
    @ObservedObject private var ltcRoutingStore = LTCRoutingStore.shared
    @AppStorage("transport.countdownMode") private var countdownModeRaw = TransportBar.CountdownMode.time.rawValue

    private var countdownMode: TransportBar.CountdownMode {
        TransportBar.CountdownMode(rawValue: countdownModeRaw) ?? .time
    }

    var body: some View {
        // Flat bottom bar (Figma 318:1309): panel background with a single top
        // hairline — no rounded card, no side/bottom borders. Zones are
        // left-grouped on a uniform divider gap (the trailing Spacer leaves the
        // empty space on the right), not pushed apart by a flexible spacer.
        HStack(spacing: 0) {
            controlZone
            divider
            readoutZone
            divider
            nextCueZone
            Spacer(minLength: 0)
        }
        .background(DS.Color.panel)
        .overlay(alignment: .top) { DS.Color.border.frame(height: 1) }
        // `.contain` keeps the bar itself queryable AND lets XCUITest walk to
        // the child controls/readouts — without it, the container identifier
        // collapses the subtree (same pattern as EditorModeSwitcher).
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("transportControls")
    }

    private var divider: some View {
        DS.Color.border.frame(width: 1).frame(maxHeight: .infinity)
    }

    // MARK: - Control zone

    private var controlZone: some View {
        HStack(spacing: DS.Space.sm) {
            iconButton("backward.end.fill", id: "transportPrevCue", help: "Previous cue", action: onStepPrevCue)
            iconButton(
                engine.isPlaying ? "pause.fill" : "play.fill",
                id: "transportPlayPause",
                help: "Play / Pause",
                primary: true
            ) {
                engine.toggle()
            }
            iconButton("forward.end.fill", id: "transportNextCue", help: "Next cue", action: onStepNextCue)
        }
        .padding(.horizontal, DS.Space.lg)
        .padding(.vertical, DS.Space.md)
    }

    private func iconButton(
        _ symbol: String,
        id: String,
        help: String,
        primary: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: primary ? 15 : 12, weight: .medium)) // off-grid: SF Symbol glyph size
                .frame(width: primary ? 34 : 30, height: primary ? 34 : 30)
                .background(primary ? DS.Color.ink : DS.Color.surface)
                .foregroundStyle(primary ? DS.Color.inkOn : DS.Color.textPrimary)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.sm)
                        .strokeBorder(DS.Color.border)
                        .opacity(primary ? 0 : 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityIdentifier(id)
    }

    // MARK: - Readout zone

    private var readoutZone: some View {
        HStack(spacing: DS.Space.sm) {
            Text(TimeFormat.smpte(engine.currentTime, rate: timecodeSettings.framerate))
                .font(DS.Text.monoHero)
                .foregroundStyle(DS.Color.textPrimary)
                .accessibilityIdentifier("currentTimeReadout")
            if mediaDuration > 0 {
                Text("/ \(TimeFormat.smpte(mediaDuration, rate: timecodeSettings.framerate))")
                    .font(DS.Text.mono)
                    .foregroundStyle(DS.Color.textTertiary)
            }
            PlaybackRateBadge(engine: engine, ltcEnabled: ltcRoutingStore.settings.isEnabled)
            PlaybackModeBadge(mode: playbackMode)
            if ltcRoutingStore.settings.isEnabled {
                Text("SMPTE \(smpteReadout)")
                    .font(DS.Text.mono)
                    .foregroundStyle(DS.Color.textSecondary)
                    .accessibilityIdentifier("smpteTimecode")
                    .help(smpteReadoutHelp)
            }
        }
        .padding(.horizontal, DS.Space.lg)
    }

    /// The SMPTE timecode at the playhead — the active file's striped LTC when
    /// it has any, otherwise derived from the project settings + active item.
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
        return "SMPTE timecode at the playhead (\(timecodeSettings.framerate.displayName);"
            + " edit in Tools → Timecode Settings…)."
    }

    // MARK: - Next-cue zone

    @ViewBuilder
    private var nextCueZone: some View {
        if let interval = TransportBar.nextCueInterval(currentTime: engine.currentTime, cues: cues) {
            let tempo = TransportBar.activeBPM(currentTime: engine.currentTime, cues: cues)
            let label = TransportBar.countdownLabel(
                mode: countdownMode,
                interval: interval,
                activeTempo: tempo,
                rate: timecodeSettings.framerate
            )
            Button(action: cycleCountdownMode) {
                VStack(alignment: .leading, spacing: DS.Space.xs / 2) {
                    // Decorative caps label — hidden from AX so the toggle
                    // button's composed label stays just the countdown value.
                    Text("Next Cue").dsSectionHeader().accessibilityHidden(true)
                    Text(label)
                        .font(DS.Text.mono)
                        .foregroundStyle(DS.Color.textPrimary)
                        .accessibilityIdentifier("nextCueCountdown")
                }
            }
            .buttonStyle(.plain)
            .help(countdownMode == .beats && tempo == nil
                  ? "Set a tempo on a cue to enable beat countdown. Click to switch back to time."
                  : "Click to switch between time and beat countdown.")
            .accessibilityIdentifier("nextCueCountdownToggle")
            .padding(.horizontal, DS.Space.lg)
            .padding(.vertical, DS.Space.md)
        }
    }

    private func cycleCountdownMode() {
        countdownModeRaw = (countdownMode == .time ? TransportBar.CountdownMode.beats : .time).rawValue
    }
}
