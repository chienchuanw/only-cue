import QuartzCore
import SwiftUI

/// Continuous playhead-follow scrolling for `WaveformContainer` (#677, #681).
/// Split into its own file so `WaveformContainer.swift` stays under the
/// `file_length` cap.
extension WaveformContainer {
    /// Offsets the zoomable content and clips it to the viewport. While following
    /// (playing, zoomed, Auto-Scroll on) the offset is recomputed each frame from
    /// the interpolated time — the SAME sample the playhead reads via
    /// `overrideTime` — so they stay locked at `followFraction` with no cross-frame
    /// lag (no pause jump, #677) or desync jitter at high zoom (#681), and it is
    /// pixel-snapped so the envelope translates without shimmer. Otherwise the
    /// stored offset (manual scroll / zoom / 1×) is used.
    @ViewBuilder
    func offsetScrollContent(buckets: [WaveformBucket], width: CGFloat, contentWidth: CGFloat, height: CGFloat) -> some View {
        // Build the heavy static layer ONCE, here — not inside the per-frame
        // TimelineView — so its wide Canvas is rasterized once and only
        // translated each frame (#681).
        let base = staticScrollContent(buckets: buckets, width: width, contentWidth: contentWidth, height: height)
        if isFollowing(viewportWidth: width) {
            // One renderedTime sample per frame drives both the offset and the
            // playhead (via `overrideTime`) — no cross-view desync jitter (#681).
            TimelineView(.animation) { _ in
                let time = followRenderedTime()
                let offset = followOffset(time: time, viewportWidth: width, contentWidth: contentWidth)
                followLayers(
                    base: base,
                    playhead: playheadLayer(overrideTime: time, contentWidth: contentWidth, height: height),
                    offset: offset,
                    width: width,
                    height: height
                )
            }
        } else {
            followLayers(
                base: base,
                playhead: playheadLayer(overrideTime: nil, contentWidth: contentWidth, height: height),
                offset: scrollOffset,
                width: width,
                height: height
            )
        }
    }

    /// Overlays the (already-built) static `base` and the per-frame `playhead`,
    /// both shifted by the same offset, then clips to the viewport. `base` is
    /// passed in so it is created once and merely translated each frame (#681).
    func followLayers(
        base: some View,
        playhead: some View,
        offset: CGFloat,
        width: CGFloat,
        height: CGFloat
    ) -> some View {
        ZStack(alignment: .topLeading) {
            base.offset(x: -offset)
            playhead.offset(x: -offset)
        }
        .frame(width: width, height: height, alignment: .leading)
        .clipped()
    }

    /// True while continuous playhead-follow is active: playing, zoomed in, and
    /// the Auto-Scroll preference on. Gates the per-frame follow offset (#677).
    func isFollowing(viewportWidth: CGFloat) -> Bool {
        guard let engine else { return false }
        return zoom.followsPlayhead && engine.isPlaying && zoom.zoom > 1 && loadedDuration > 0 && viewportWidth > 0
    }

    /// The pixel-snapped follow offset for a given playhead time. Takes the time
    /// explicitly so the offset and the playhead line share one per-frame sample
    /// (#681).
    func followOffset(time: TimeInterval, viewportWidth: CGFloat, contentWidth: CGFloat) -> CGFloat {
        let playheadContentX = CueMarkersGeometry.position(
            forTime: time,
            width: contentWidth,
            duration: loadedDuration
        )
        return zoom.snappedFollowScrollOffset(
            playheadContentX: playheadContentX,
            viewportWidth: viewportWidth,
            contentWidth: contentWidth,
            displayScale: displayScale
        )
    }

    /// The interpolated playhead time — one basis for the offset + playhead (#677).
    func followRenderedTime() -> TimeInterval {
        guard let engine else { return 0 }
        if let scrubTime = scrub.state?.scrubTime { return scrubTime }
        return PlayheadInterpolator.renderedTime(
            observedTime: engine.currentTime,
            observedAt: engine.currentTimeObservedAt,
            now: CACurrentMediaTime(),
            rate: Double(engine.rate),
            duration: loadedDuration,
            outputLatency: engine.outputLatency
        )
    }

    /// On pause, snapshot the current follow offset into the stored scroll offset
    /// so the frozen frame matches the last followed frame (no jump) and manual
    /// scroll resumes from the right place (#677). No-op when not following.
    func persistFollowOffsetOnPause() {
        guard zoom.followsPlayhead, zoom.zoom > 1, viewportWidth > 0, loadedDuration > 0 else { return }
        let contentWidth = zoom.contentWidth(viewportWidth: viewportWidth)
        scrollOffset = followOffset(time: followRenderedTime(), viewportWidth: viewportWidth, contentWidth: contentWidth)
    }
}
