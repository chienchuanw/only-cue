import QuartzCore
import SwiftUI

/// Ruler shown directly below the waveform when LTC routing is enabled. It draws
/// `LTCTickGenerator` ticks + labels edge-to-edge across its width with a moving
/// playhead line (#653) that tracks playback. The strip carries no header now —
/// it shares the waveform's horizontal inset (`PreviewLayout.trackHorizontalInset`)
/// so its playhead stays collinear with the waveform's (#663). Non-interactive
/// (no hit testing, so clicks pass through to the click-to-seek surface above;
/// the playhead is display-only). The per-clip LTC mute lives in the media
/// right-click menu (#663).
struct LTCStrip: View {

    let item: MediaItem
    let framerate: SMPTEFramerate
    let duration: TimeInterval
    /// Drives the moving playhead (#653). nil → no playhead (previews/tests
    /// without a playback context).
    var engine: PlayerEngine?
    /// The waveform's shared horizontal-zoom controller (#669). nil → unzoomed
    /// (previews/tests). When set, the ruler is drawn across the same zoomed
    /// content width and shifted by the same `scrollOffset` as the waveform, so
    /// the two playheads stay collinear at any zoom/scroll.
    var zoom: WaveformZoomController?

    /// Device pixel scale — the follow offset is snapped to this grid so the
    /// ruler tracks the waveform's shimmer-free scroll (#677).
    @Environment(\.displayScale) private var displayScale

    private static let stripHeight: CGFloat = 34
    private static let playheadLineWidth: CGFloat = 1

    /// Tick-label placement pinned to Figma 318:1308 (#553, audit `## ltc-strip`).
    /// Off-grid (no DS token); `LTCStripMetricsTests` guards it.
    enum Metrics {
        static let tickLabelTop: CGFloat = 4       // Figma label top-[4px]
    }

    var body: some View {
        ruler
            .frame(height: Self.stripHeight)
            .background(DS.Color.surfaceSunken)
            // Figma 318:1308 — the strip is bounded top and bottom by a hairline.
            .dsHairline(edge: .top)
            .dsHairline(edge: .bottom)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("ltcStrip")
    }

    private var ruler: some View {
        GeometryReader { proxy in
            // Mirror the waveform's zoomed content width + scroll offset (#669):
            // draw ticks/playhead across `contentWidth`, shift by the scroll
            // offset, and clip to the viewport — the same window the waveform
            // shows. At zoom == 1 this is `contentWidth == viewport`, `offset ==
            // 0` (#663).
            let viewport = proxy.size.width
            let contentWidth = zoom?.contentWidth(viewportWidth: viewport) ?? viewport
            rulerContent(viewport: viewport, contentWidth: contentWidth, height: proxy.size.height)
        }
        .allowsHitTesting(false)
    }

    /// While following (playing, zoomed, Auto-Scroll on) recompute the offset
    /// every frame from the same interpolated time the waveform uses (#677) — the
    /// stored `scrollOffset` is only persisted on pause now, so the ruler must
    /// derive its own per-frame offset to stay collinear and shimmer-free.
    /// Otherwise mirror the waveform's stored (rendered) scroll offset (#669).
    @ViewBuilder
    private func rulerContent(viewport: CGFloat, contentWidth: CGFloat, height: CGFloat) -> some View {
        if isFollowing(viewport: viewport) {
            TimelineView(.animation) { _ in
                rulerStack(
                    viewport: viewport,
                    contentWidth: contentWidth,
                    height: height,
                    scrollOffset: followOffset(viewport: viewport, contentWidth: contentWidth)
                )
            }
        } else {
            rulerStack(
                viewport: viewport,
                contentWidth: contentWidth,
                height: height,
                scrollOffset: zoom?.renderedScrollOffset ?? 0
            )
        }
    }

    private func rulerStack(viewport: CGFloat, contentWidth: CGFloat, height: CGFloat, scrollOffset: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, size in
                draw(into: context, size: size)
            }
            playhead(width: contentWidth, height: height)
        }
        .frame(width: contentWidth, height: height, alignment: .leading)
        .offset(x: -scrollOffset)
        .frame(width: viewport, height: height, alignment: .leading)
        .clipped()
    }

    private func isFollowing(viewport: CGFloat) -> Bool {
        guard let zoom, let engine else { return false }
        return zoom.followsPlayhead && engine.isPlaying && zoom.zoom > 1 && duration > 0 && viewport > 0
    }

    private func followOffset(viewport: CGFloat, contentWidth: CGFloat) -> CGFloat {
        guard let zoom else { return 0 }
        let playheadContentX = CueMarkersGeometry.position(
            forTime: renderedTime(),
            width: contentWidth,
            duration: duration
        )
        return zoom.snappedFollowScrollOffset(
            playheadContentX: playheadContentX,
            viewportWidth: viewport,
            contentWidth: contentWidth,
            displayScale: displayScale
        )
    }

    /// The interpolated playhead time — shared by the follow offset and the
    /// ruler's own moving playhead so they track one time basis (#653, #677).
    private func renderedTime() -> TimeInterval {
        guard let engine else { return 0 }
        return PlayheadInterpolator.renderedTime(
            observedTime: engine.currentTime,
            observedAt: engine.currentTimeObservedAt,
            now: CACurrentMediaTime(),
            rate: Double(engine.rate),
            duration: duration,
            outputLatency: engine.outputLatency
        )
    }

    /// Moving playhead line (#653). Reuses the waveform's smooth interpolation
    /// (`PlayheadInterpolator`, driven by `TimelineView(.animation)`) and pure
    /// time→x mapping (`CueMarkersGeometry.position`), and its 1pt primary-color
    /// style. Maps across the ruler's full width, which now shares the waveform's
    /// inset — so this playhead is collinear with the waveform's (#663).
    @ViewBuilder
    private func playhead(width: CGFloat, height: CGFloat) -> some View {
        if engine != nil, duration > 0 {
            TimelineView(.animation) { _ in
                let xPosition = CueMarkersGeometry.position(forTime: renderedTime(), width: width, duration: duration)
                Rectangle()
                    .fill(Color.primary)
                    .frame(width: Self.playheadLineWidth, height: height)
                    .opacity(0.85) // matches the waveform playhead so the ticks read through
                    .offset(x: xPosition - Self.playheadLineWidth / 2)
                    .accessibilityElement()
                    .accessibilityLabel("LTC playhead")
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
