import QuartzCore
import SwiftUI

/// Lane shown below the waveform when LTC routing is enabled. A fixed-width
/// header carries the mute toggle + active clip's file name; the trailing
/// ruler draws `LTCTickGenerator` ticks + labels across the lane's width, with a
/// moving playhead line (#653) that tracks playback. Strip is non-interactive
/// (no hit testing on the ruler so clicks pass through to the click-to-seek
/// surface above; the playhead is display-only).
struct LTCStrip: View {

    let item: MediaItem
    let framerate: SMPTEFramerate
    let duration: TimeInterval
    let onToggleMute: () -> Void
    /// Drives the moving playhead (#653). nil → no playhead (previews/tests
    /// without a playback context).
    var engine: PlayerEngine?

    private static let laneHeaderWidth: CGFloat = 150
    private static let stripHeight: CGFloat = 34
    private static let playheadLineWidth: CGFloat = 1

    /// Header/ruler spacing pinned to Figma 318:1308 (#553, audit `## ltc-strip`).
    /// Off-grid (no DS token); `LTCStripMetricsTests` guards them.
    enum Metrics {
        static let headerGap: CGFloat = 6          // icon ↔ label, Figma gap-[6px]
        static let headerHPadding: CGFloat = 10    // Figma px-[10px]
        static let iconWidth: CGFloat = 17         // Figma ic-spkr 17×14
        static let iconHeight: CGFloat = 14
        static let rulerLeadingInset: CGFloat = 8  // Figma ruler pl-[8px]
        static let tickLabelTop: CGFloat = 4       // Figma label top-[4px]
    }

    var body: some View {
        HStack(spacing: 0) {
            header
            ruler
        }
        .frame(height: Self.stripHeight)
        .background(DS.Color.surfaceSunken)
        // Figma 318:1308 — the strip is bounded top and bottom by a hairline.
        .dsHairline(edge: .top)
        .dsHairline(edge: .bottom)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ltcStrip")
    }

    private var header: some View {
        HStack(spacing: Metrics.headerGap) { // off-grid: Figma gap-[6px]
            Button(action: onToggleMute) {
                Image(systemName: item.ltcMuted ? "speaker.slash.fill" : "speaker.fill")
                    .frame(width: Metrics.iconWidth, height: Metrics.iconHeight) // off-grid: Figma 17×14
            }
            .buttonStyle(.plain)
            .help(item.ltcMuted ? "Unmute LTC for this clip" : "Mute LTC for this clip")
            .accessibilityLabel(item.ltcMuted ? "LTC muted" : "LTC unmuted")
            .accessibilityIdentifier("ltcMuteToggle.\(item.id.uuidString)")
            Text("LTC · \(item.resolvedName)")
                .font(DS.Text.small) // Figma: Inter Regular 11 (sans), not mono
                .foregroundStyle(DS.Color.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, Metrics.headerHPadding) // off-grid: Figma px-[10px]
        .frame(width: Self.laneHeaderWidth, alignment: .leading)
        // The header block is panel-tinted; the ruler area keeps the sunken fill.
        .frame(maxHeight: .infinity)
        .background(DS.Color.panel)
    }

    private var ruler: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    draw(into: context, size: size)
                }
                playhead(width: proxy.size.width, height: proxy.size.height)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        // off-grid: Figma ruler frame pl-[8px] — first tick is inset from the
        // panel-header boundary rather than butting against it.
        .padding(.leading, Metrics.rulerLeadingInset)
        .allowsHitTesting(false)
    }

    /// Moving playhead line (#653). Reuses the waveform's smooth interpolation
    /// (`PlayheadInterpolator`, driven by `TimelineView(.animation)`) and pure
    /// time→x mapping (`CueMarkersGeometry.position`), and its 1pt primary-color
    /// style. Maps across the ruler's own width — proportional to, not
    /// pixel-aligned with, the (differently-inset) waveform playhead.
    @ViewBuilder
    private func playhead(width: CGFloat, height: CGFloat) -> some View {
        if let engine, duration > 0 {
            TimelineView(.animation) { _ in
                let time = PlayheadInterpolator.renderedTime(
                    observedTime: engine.currentTime,
                    observedAt: engine.currentTimeObservedAt,
                    now: CACurrentMediaTime(),
                    rate: Double(engine.rate),
                    duration: duration,
                    outputLatency: engine.outputLatency
                )
                let xPosition = CueMarkersGeometry.position(forTime: time, width: width, duration: duration)
                Rectangle()
                    .fill(Color.primary)
                    .frame(width: Self.playheadLineWidth, height: height)
                    .opacity(0.85)
                    .offset(x: xPosition - Self.playheadLineWidth / 2)
                    .accessibilityElement()
                    .accessibilityIdentifier("ltcStripPlayhead")
            }
        }
    }

    private func draw(into context: GraphicsContext, size: CGSize) {
        guard duration > 0, size.width > 0 else { return }
        let pxPerSecond = size.width / CGFloat(duration)
        let bucket = LTCTickInterval.pick(secondsVisible: duration, pxPerSecond: pxPerSecond)
        let ticks = LTCTickGenerator.ticks(
            duration: duration,
            framerate: framerate,
            startTimecodeFrames: item.startTimecodeFrames,
            bucketSeconds: bucket,
            contentWidth: size.width
        )
        // Figma 318:1308: ticks are bottom-aligned in `border-strong` (major 9 /
        // minor 5) with a 2pt bottom inset; labels sit at the top in tertiary.
        let bottomInset: CGFloat = 2
        let strokeColor = GraphicsContext.Shading.color(DS.Color.borderStrong)
        for tick in ticks {
            let tickHeight: CGFloat = tick.isMajor ? 9 : 5
            let baseY = size.height - bottomInset
            var path = Path()
            path.move(to: CGPoint(x: tick.xPosition, y: baseY))
            path.addLine(to: CGPoint(x: tick.xPosition, y: baseY - tickHeight))
            context.stroke(path, with: strokeColor, lineWidth: 1)
            guard tick.isMajor else { continue }
            let text = Text(tick.label)
                .font(DS.Text.monoMicro)
                .foregroundColor(DS.Color.textTertiary)
            context.draw(
                text,
                at: CGPoint(x: tick.xPosition + 2, y: Metrics.tickLabelTop), // off-grid: Figma top-[4px]
                anchor: .topLeading
            )
        }
    }
}
