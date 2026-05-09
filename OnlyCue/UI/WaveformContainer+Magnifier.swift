import SwiftUI

/// Wires `WaveformZoomMagnifier` to the two existing zoom controllers.
/// Lives in a separate file to keep the magnifier wiring out of the dense
/// `WaveformContainer` body (matches the prior `+ZoomRails.swift` pattern).
extension WaveformContainer {

    var magnifier: some View {
        WaveformZoomMagnifier(
            horizontalZoom: zoom.zoom,
            verticalZoom: verticalZoom.zoom,
            isVisible: isHoveringWaveform || hintShowing,
            onDrag: applyMagnifierDrag,
            onResetRequested: applyMagnifierReset
        )
    }

    func applyMagnifierDrag(_ drag: MagnifierDrag) {
        guard viewportWidth > 0 else { return }

        // Horizontal axis: route through the existing setZoom-via-applyDrag path
        // so scroll-anchor + clamping stay correct. The magnifier sits in a
        // fixed corner — center-anchor (0.5) is the only sensible default.
        var offset = scrollOffset
        zoom.applyDrag(
            translation: drag.translationX,
            baseline: drag.hBaseline,
            anchorFraction: 0.5,
            viewportWidth: viewportWidth,
            scrollOffset: &offset
        )
        scrollOffset = offset
        pinchBaseline = zoom.zoom

        // Vertical axis: scales rendering in place, no scroll-offset coupling.
        verticalZoom.applyDrag(
            translation: drag.translationY,
            baseline: drag.vBaseline
        )

        syncAnchorFromOffset(viewportWidth: viewportWidth)
    }

    func applyMagnifierReset() {
        applyZoomReset()    // existing helper: resets horizontal + scrollOffset + leadingAnchor + pinchBaseline
        verticalZoom.reset()
    }
}
