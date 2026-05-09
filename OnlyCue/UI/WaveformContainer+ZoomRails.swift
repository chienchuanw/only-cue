import SwiftUI

/// Hover-revealed zoom-rail subviews. Lives in a separate file so the rail wiring
/// stays out of `WaveformContainer`'s body-length budget — the container is dense
/// with horizontal-zoom + scroll-anchor + auto-follow plumbing already.
extension WaveformContainer {

    var verticalRail: some View {
        WaveformZoomRail(
            axis: .vertical,
            zoom: verticalZoom.zoom,
            isVisible: isHoveringWaveform || hintShowing,
            onDrag: { translation, baseline, _ in
                verticalZoom.applyDrag(translation: translation, baseline: baseline)
            },
            onResetRequested: { verticalZoom.reset() }
        )
        .frame(maxHeight: .infinity, alignment: .trailing)
    }

    var horizontalRail: some View {
        WaveformZoomRail(
            axis: .horizontal,
            zoom: zoom.zoom,
            isVisible: isHoveringWaveform || hintShowing,
            onDrag: applyHorizontalRailDrag,
            onResetRequested: { applyZoomReset() }
        )
        .frame(maxWidth: .infinity, alignment: .bottom)
    }

    private func applyHorizontalRailDrag(
        translation: CGFloat,
        baseline: CGFloat,
        anchor: CGFloat
    ) {
        guard viewportWidth > 0 else { return }
        var offset = scrollOffset
        zoom.applyDrag(
            translation: translation,
            baseline: baseline,
            anchorFraction: anchor,
            viewportWidth: viewportWidth,
            scrollOffset: &offset
        )
        scrollOffset = offset
        pinchBaseline = zoom.zoom
        syncAnchorFromOffset(viewportWidth: viewportWidth)
    }
}
