import Foundation

/// Controls the vertical (amplitude-axis) scale factor applied to rendered waveform peaks.
///
/// Mirrors `WaveformZoomController` but without the scroll/anchor logic — vertical zoom
/// scales the peak rendering in place, capped at the canvas mid-line by the consumer
/// (`WaveformView`), so there's no viewport / content-width math to thread through.
@Observable
@MainActor
final class WaveformVerticalZoomController {

    static let minZoom: CGFloat = 1
    static let maxZoom: CGFloat = 8
    static let zoomStep: CGFloat = 1.5
    static let dragPixelsPerStep: CGFloat = 60

    private(set) var zoom: CGFloat = 1

    func setZoom(_ next: CGFloat) {
        zoom = min(max(next, Self.minZoom), Self.maxZoom)
    }

    func zoomIn() { setZoom(zoom * Self.zoomStep) }
    func zoomOut() { setZoom(zoom / Self.zoomStep) }
    func reset() { zoom = 1 }

    /// Apply a continuous drag translation to a baseline zoom captured at drag start.
    /// Negative `translation` = drag up = zoom in; `dragPixelsPerStep` of drag in either
    /// direction multiplies (or divides) the baseline by `zoomStep`. Final value is
    /// clamped to `[minZoom, maxZoom]`. Capturing baseline (vs delta-from-current) avoids
    /// clamping artifacts during a single continuous drag.
    func applyDrag(translation: CGFloat, baseline: CGFloat) {
        let raw = baseline * pow(Self.zoomStep, -translation / Self.dragPixelsPerStep)
        setZoom(raw)
    }
}
