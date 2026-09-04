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
    /// Steps to the previous / next song (media item) and plays it (#753).
    /// Supplied by `DocumentView`.
    var onStepPrevSong: () -> Void = {}
    var onStepNextSong: () -> Void = {}
    /// Whether a previous / next song exists — drives the song buttons' disabled
    /// state so they stop at the list boundary (no wrap, #753).
    var canStepPrevSong: Bool = true
    var canStepNextSong: Bool = true
    /// The active Show-mode cue-type filter (`DocumentView.showGoTypeID`): nil =
    /// All cues. Kept equal to what `stepPlayhead` walks so the cue buttons
    /// disable exactly when there is no prev/next cue to step to (#753).
    var activeCueTypeID: CuePointType.ID?
    /// Show-mode GO — walk to the next cue and play. nil outside Show mode, which
    /// hides the GO button entirely. Supplied by `DocumentView` (#645).
    var onGo: (() -> Void)?

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
        // Order (Figma TransportControls 34:45, #753): song navigation on the
        // outer flanks (end-icons), cue navigation inner (double-triangle),
        // play centered. Song jumps whole media items; cue moves within one.
        HStack(spacing: Metrics.buttonGap) {
            iconButton(
                "backward.end.fill",
                id: "transportPrevSong",
                help: "Previous song",
                enabled: canStepPrevSong,
                action: onStepPrevSong
            )
            iconButton(
                "backward.fill",
                id: "transportPrevCue",
                help: "Previous cue",
                enabled: hasPrevCue,
                action: onStepPrevCue
            )
            iconButton(
                engine.isPlaying ? "pause.fill" : "play.fill",
                id: "transportPlayPause",
                help: "Play / Pause",
                primary: true
            ) {
                engine.toggle()
            }
            iconButton(
                "forward.fill",
                id: "transportNextCue",
                help: "Next cue",
                enabled: hasNextCue,
                action: onStepNextCue
            )
            iconButton(
                "forward.end.fill",
                id: "transportNextSong",
                help: "Next song",
                enabled: canStepNextSong,
                action: onStepNextSong
            )
            if let onGo {
                goButton(action: onGo)
            }
        }
    }

    /// Whether a prev / next cue exists relative to the playhead (#753). Read of
    /// `engine.currentTime` keeps these live as playback moves, so the cue
    /// buttons disable at the first / last cue. Mirrors `stepPlayhead`'s walk
    /// (same `typeID` filter) so button state and action always agree.
    private var hasPrevCue: Bool {
        activeItem?.cue(steppingFrom: engine.currentTime, direction: .previous, typeID: activeCueTypeID) != nil
    }

    private var hasNextCue: Bool {
        activeItem?.cue(steppingFrom: engine.currentTime, direction: .next, typeID: activeCueTypeID) != nil
    }

    /// The Show-mode GO button — a labelled, emphasised control (not a glyph),
    /// since it is the show caller's primary action. Only rendered in Show mode
    /// (when `onGo` is non-nil).
    private func goButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("GO")
                .font(DS.Text.heading)
                .foregroundStyle(DS.Color.onCueIndigo)
                .frame(width: Metrics.primaryButtonWidth, height: Metrics.primaryButtonHeight)
                .background(DS.Color.cueIndigo, in: RoundedRectangle(cornerRadius: DS.Radius.sm))
        }
        .buttonStyle(.plain)
        .help("GO — next cue")
        .accessibilityIdentifier("transportGo")
    }

    private func iconButton(
        _ symbol: String,
        id: String,
        help: String,
        primary: Bool = false,
        enabled: Bool = true,
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
        .dsDisabledDim(!enabled)  // stop + dim at the list/cue boundary (#753)
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
            PlaybackRateBadge(engine: engine, timecodeOutputEnabled: TimecodeOutputInterlock.isEngagedNow)
            PlaybackModeBadge(mode: playbackMode)
            if TimecodeReadout.isVisible(
                hasFileTimecode: stripedTimecode != nil,
                ltcOutputEnabled: ltcRoutingStore.settings.isEnabled
            ) {
                Text("\(TimecodeReadout.prefix(hasFileTimecode: stripedTimecode != nil)) \(smpteReadout)")
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
            var help = "SMPTE timecode read from the media file's LTC track."
            // Be explicit when the two disagree: the generator keeps emitting the
            // project-settings timecode, so with output on this readout is *not*
            // what is going out the LTC port (#712).
            if ltcRoutingStore.settings.isEnabled {
                help += " LTC output is generating the project-settings timecode, which may differ."
            }
            return help
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
