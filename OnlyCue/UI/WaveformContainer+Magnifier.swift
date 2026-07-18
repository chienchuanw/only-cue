import SwiftUI

/// Wires `WaveformZoomMagnifier` to the horizontal zoom controller.
/// Lives in a separate file to keep the magnifier wiring out of the dense
/// `WaveformContainer` body (matches the prior `+ZoomRails.swift` pattern).
extension WaveformContainer {

    var magnifier: some View {
        WaveformZoomMagnifier(
            horizontalZoom: zoom.zoom,
            isVisible: isHoveringWaveform || hintShowing,
            onDrag: applyMagnifierDrag,
            onResetRequested: applyMagnifierReset
        )
    }

    func applyMagnifierDrag(_ drag: MagnifierDrag) {
        guard viewportWidth > 0 else { return }

        // Route through the existing setZoom-via-applyDrag path so
        // scroll-anchor + clamping stay correct. The magnifier sits in a
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
    }

    func applyMagnifierReset() {
        applyZoomReset()    // existing helper: resets zoom + scrollOffset + pinchBaseline
    }
}
