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

    private(set) var zoom: CGFloat = 1

    func setZoom(_ next: CGFloat) {
        zoom = min(max(next, Self.minZoom), Self.maxZoom)
    }

    func zoomIn() { setZoom(zoom * Self.zoomStep) }
    func zoomOut() { setZoom(zoom / Self.zoomStep) }
    func reset() { zoom = 1 }
}
