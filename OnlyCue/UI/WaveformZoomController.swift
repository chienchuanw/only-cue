import Foundation

@Observable
@MainActor
final class WaveformZoomController {

    static let minZoom: CGFloat = 1
    // Raised 16→64 (#667) so long tracks can be zoomed in far enough for precise
    // cue placement — a ~4-minute clip then shows ~4s across the viewport.
    static let maxZoom: CGFloat = 64
    static let zoomStep: CGFloat = 1.5
    static let dragPixelsPerStep: CGFloat = 60
    /// The fraction of the viewport the playhead is pinned at during continuous
    /// auto-follow (#675) — ~1/3 from the left, so ~2/3 of the view is
    /// look-ahead (upcoming waveform / cues).
    static let followFraction: CGFloat = 1.0 / 3.0

    private(set) var zoom: CGFloat = 1
    var followsPlayhead: Bool = true

    /// Cached pixel-offset of the scroll view's leading edge. Updated by zoom
    /// helpers that touch scroll position; read by drag / magnifier extensions.
    /// Stored here (on the `@Observable` reference type) so the value persists
    /// across SwiftUI struct re-creations and is directly mutable in tests.
    ///
    /// Trade-off: the auto-follow path writes this every playback frame. Because
    /// `WaveformZoomController` is `@Observable`, those writes notify every view
    /// that observes any property of this controller — including views that only
    /// read `zoom`. SwiftUI's diff may suppress actual redraws when no relevant
    /// input changed, but the isolation guarantee that `@State var scrollOffset`
    /// gave us (re-render scope limited to the property's reader) is gone. If
    /// scroll-tick re-renders ever measure as a problem, split `scrollOffset`
    /// and `viewportWidth` into a separate `@Observable` `WaveformScrollState`
    /// class.
    var scrollOffset: CGFloat = 0

    /// The waveform's actual rendered horizontal scroll offset, which the LTC
    /// strip mirrors so its playhead lands exactly under the waveform's on-screen
    /// playhead (#669). The waveform now renders via a continuous pixel offset
    /// (#675), so this simply equals `scrollOffset` (no anchor snapping).
    var renderedScrollOffset: CGFloat { scrollOffset }

    /// Width of the visible viewport in points. Set by `GeometryReader` on each
    /// layout pass. Stored on the reference type so it survives struct copies and
    /// is directly settable from tests without going through `@State`.
    var viewportWidth: CGFloat = 0

    /// The zoomed content width for a given viewport width — `viewportWidth ×
    /// zoom`, never below the viewport. Shared by the waveform and the LTC strip
    /// (#669) so their time→x tracks are sized identically and their playheads
    /// stay collinear at any zoom.
    func contentWidth(viewportWidth: CGFloat) -> CGFloat {
        max(viewportWidth * zoom, viewportWidth)
    }

    func setZoom(
        _ next: CGFloat,
        anchorFraction: CGFloat,
        viewportWidth: CGFloat,
        scrollOffset: inout CGFloat
    ) {
        let clampedZoom = min(max(next, Self.minZoom), Self.maxZoom)
        guard viewportWidth > 0 else {
            zoom = clampedZoom
            return
        }
        let oldContentWidth = viewportWidth * zoom
        let anchorContentX = scrollOffset + anchorFraction * viewportWidth
        let timeFraction = oldContentWidth > 0 ? anchorContentX / oldContentWidth : 0

        let newContentWidth = viewportWidth * clampedZoom
        let newAnchorContentX = timeFraction * newContentWidth
        let newOffset = newAnchorContentX - anchorFraction * viewportWidth
        let maxOffset = max(newContentWidth - viewportWidth, 0)
        scrollOffset = min(max(newOffset, 0), maxOffset)
        zoom = clampedZoom
    }

    func zoomIn(
        anchorFraction: CGFloat = 0.5,
        viewportWidth: CGFloat,
        scrollOffset: inout CGFloat
    ) {
        setZoom(
            zoom * Self.zoomStep,
            anchorFraction: anchorFraction,
            viewportWidth: viewportWidth,
            scrollOffset: &scrollOffset
        )
    }

    func zoomOut(
        anchorFraction: CGFloat = 0.5,
        viewportWidth: CGFloat,
        scrollOffset: inout CGFloat
    ) {
        setZoom(
            zoom / Self.zoomStep,
            anchorFraction: anchorFraction,
            viewportWidth: viewportWidth,
            scrollOffset: &scrollOffset
        )
    }

    /// Restores 1× zoom and a zero scroll offset, e.g. on media load. Does NOT
    /// touch `followsPlayhead`: that is the persisted "Auto-Scroll Waveform"
    /// user preference (issue #532), driven from `@AppStorage`, not transient
    /// view state — clobbering it here would silently re-enable auto-scroll on
    /// the next clip after the user disabled it.
    func reset(scrollOffset: inout CGFloat) {
        if zoom == 1 && scrollOffset == 0 { return }
        zoom = 1
        scrollOffset = 0
    }

    /// Apply a continuous drag translation to a baseline zoom captured at drag start,
    /// anchored on a horizontal cursor fraction so zoom centers on what the user is
    /// pointing at. Positive `translation` = drag right = zoom in; one
    /// `dragPixelsPerStep` of drag in either direction multiplies (or divides) the
    /// baseline by `zoomStep`. Routes through `setZoom(...)` so scroll-offset
    /// anchoring is preserved.
    func applyDrag(
        translation: CGFloat,
        baseline: CGFloat,
        anchorFraction: CGFloat,
        viewportWidth: CGFloat,
        scrollOffset: inout CGFloat
    ) {
        let raw = baseline * pow(Self.zoomStep, translation / Self.dragPixelsPerStep)
        setZoom(
            raw,
            anchorFraction: anchorFraction,
            viewportWidth: viewportWidth,
            scrollOffset: &scrollOffset
        )
    }

    /// The continuous auto-follow scroll offset (#675): the offset that pins the
    /// playhead at `followFraction` of the viewport, clamped to
    /// `[0, contentWidth − viewportWidth]`. Applied every frame while playing so
    /// the waveform flows smoothly under a fixed playhead (no jump-on-threshold).
    func followScrollOffset(
        playheadContentX: CGFloat,
        viewportWidth: CGFloat,
        contentWidth: CGFloat
    ) -> CGFloat {
        let target = playheadContentX - viewportWidth * Self.followFraction
        let maxOffset = max(contentWidth - viewportWidth, 0)
        return min(max(target, 0), maxOffset)
    }

    /// `followScrollOffset` aligned to whole device pixels (#677). Snapping the
    /// *render* offset to the pixel grid stops the dense waveform envelope from
    /// resampling under sub-pixel Core Animation translation — the "shimmer"
    /// during follow-scroll. `displayScale ≤ 0` (unknown scale) falls back to the
    /// unsnapped clamped offset. The clamp is re-applied after snapping so a
    /// rounded value can never sit outside `[0, contentWidth − viewportWidth]`.
    func snappedFollowScrollOffset(
        playheadContentX: CGFloat,
        viewportWidth: CGFloat,
        contentWidth: CGFloat,
        displayScale: CGFloat
    ) -> CGFloat {
        let raw = followScrollOffset(
            playheadContentX: playheadContentX,
            viewportWidth: viewportWidth,
            contentWidth: contentWidth
        )
        guard displayScale > 0 else { return raw }
        let snapped = (raw * displayScale).rounded() / displayScale
        let maxOffset = max(contentWidth - viewportWidth, 0)
        return min(max(snapped, 0), maxOffset)
    }

    /// Returns a new scroll offset that brings `targetTime` into view, centered
    /// in the viewport, when zoomed in and the target is currently off-screen;
    /// nil if there's nothing to scroll (1× zoom, zero duration) or the target
    /// is already visible. Used to focus the selected cue (#536). NOT gated on `followsPlayhead` — selecting
    /// a cue should reveal it regardless of the auto-scroll preference.
    func scrollToRevealAdjustment(
        targetTime: TimeInterval,
        duration: TimeInterval,
        viewportWidth: CGFloat,
        currentScrollOffset: CGFloat
    ) -> CGFloat? {
        guard zoom > 1, duration > 0, viewportWidth > 0 else { return nil }
        let contentWidth = viewportWidth * zoom
        let targetX = CueMarkersGeometry.position(
            forTime: targetTime,
            width: contentWidth,
            duration: duration
        )
        if targetX >= currentScrollOffset && targetX <= currentScrollOffset + viewportWidth {
            return nil // already visible — don't yank the view
        }
        let centered = targetX - viewportWidth / 2
        let maxOffset = max(contentWidth - viewportWidth, 0)
        return min(max(centered, 0), maxOffset)
    }
}
