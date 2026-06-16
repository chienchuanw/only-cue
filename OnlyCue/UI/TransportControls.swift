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

    /// Transport-bar geometry pinned to Figma 318:1310 (#555, audit
    /// `## transport-bar`). Off-grid (no DS token); `TransportControlsMetricsTests`
    /// guards them.
    enum Metrics {
        static let containerHPadding: CGFloat = 16  // Figma px-16
        static let containerVPadding: CGFloat = 10  // Figma py-10
        static let zoneGap: CGFloat = 16            // Figma gap-16 between zones/dividers
        static let dividerHeight: CGFloat = 26      // Figma h-26 (not full-bar)
        static let buttonGap: CGFloat = 6           // Figma gap-6 between transport buttons
        static let primaryButtonWidth: CGFloat = 34
        static let primaryButtonHeight: CGFloat = 28 // Figma 34×28
        static let sideButtonWidth: CGFloat = 28
        static let sideButtonHeight: CGFloat = 26    // Figma 28×26
    }

    var body: some View {
        // Flat bottom bar (Figma 318:1309/1310): panel background with a single
        // top hairline — no rounded card, no side/bottom borders. A single
        // container padding (px-16 / py-10) and a uniform 16pt gap separate the
        // zones (and their dividers); the trailing Spacer left-groups them.
        HStack(spacing: Metrics.zoneGap) {
            controlZone
            divider
            readoutZone
            divider
            nextCueZone
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Metrics.containerHPadding)
        .padding(.vertical, Metrics.containerVPadding)
        .background(DS.Color.panel)
        .overlay(alignment: .top) { DS.Color.border.frame(height: 1) }
        // `.contain` keeps the bar itself queryable AND lets XCUITest walk to
        // the child controls/readouts — without it, the container identifier
        // collapses the subtree (same pattern as EditorModeSwitcher).
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("transportControls")
    }

    /// Figma 318:1310: only the primary play/pause control carries a filled
    /// button; prev/next skip controls are plain box-less glyphs.
    static func buttonShowsChrome(primary: Bool) -> Bool { primary }

    private var divider: some View {
        // Fixed 26pt inset hairline (Figma 318:1310 h-26), vertically centered
        // by the row, rather than spanning the full bar height.
        DS.Color.border.frame(width: 1, height: Metrics.dividerHeight)
    }

    // MARK: - Control zone

    private var controlZone: some View {
        // No per-zone padding — the bar's container padding + 16pt zone gap
        // handle separation (Figma flat layout, #555).
        HStack(spacing: Metrics.buttonGap) {
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
    }

    private func iconButton(
        _ symbol: String,
        id: String,
        help: String,
        primary: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        let showsChrome = Self.buttonShowsChrome(primary: primary)
        return Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: primary ? 15 : 12, weight: .medium)) // off-grid: SF Symbol glyph size
                .frame(
                    width: primary ? Metrics.primaryButtonWidth : Metrics.sideButtonWidth,
                    height: primary ? Metrics.primaryButtonHeight : Metrics.sideButtonHeight
                )
                // Primary: filled ink button. Skip controls: box-less glyph —
                // no background, no border (Figma 318:1310).
                .background(showsChrome ? DS.Color.ink : Color.clear)
                .foregroundStyle(showsChrome ? DS.Color.inkOn : DS.Color.textPrimary)
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
        }
    }

    private func cycleCountdownMode() {
        countdownModeRaw = (countdownMode == .time ? TransportBar.CountdownMode.beats : .time).rawValue
    }
}
