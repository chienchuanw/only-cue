import XCTest
@testable import OnlyCue

/// #540: the waveform's peak columns must be positioned with the same
/// continuous `fraction * width` mapping the playhead and cue markers use
/// (`CueMarkersGeometry.position`), so a transient lines up with its playhead at
/// every zoom level and across the full width. The previous fence-post spacing
/// (`index * width / (count - 1)`) drifted from that mapping, worst at the
/// right edge.
final class WaveformColumnAlignmentTests: XCTestCase {

    func test_columnX_matchesPlayheadTimeMapping_atBucketCenter() {
        let width: CGFloat = 800
        let duration: TimeInterval = 137
        let count = 800
        for index in [0, 1, 200, 400, 799] {
            let x = WaveformView.columnX(index: index, count: count, width: width)
            // The column represents the center of its time bucket.
            let bucketCenterTime = (Double(index) + 0.5) / Double(count) * duration
            let playheadX = CueMarkersGeometry.position(
                forTime: bucketCenterTime,
                width: width,
                duration: duration
            )
            XCTAssertEqual(x, playheadX, accuracy: 0.0001, "column \(index) must sit where its time maps")
        }
    }

    func test_columnX_isMonotonicAndWithinBounds() {
        let width: CGFloat = 640
        let count = 640
        var previous: CGFloat = -1
        for index in stride(from: 0, to: count, by: 37) {
            let x = WaveformView.columnX(index: index, count: count, width: width)
            XCTAssertGreaterThanOrEqual(x, 0)
            XCTAssertLessThanOrEqual(x, width)
            XCTAssertGreaterThan(x, previous)
            previous = x
        }
    }

    func test_columnX_scalesWithWidth_forZoom() {
        // At 4x zoom the content width is 4x; the same column index maps 4x
        // farther right, matching the playhead mapping into the zoomed content.
        let count = 100
        let x1 = WaveformView.columnX(index: 50, count: count, width: 400)
        let x4 = WaveformView.columnX(index: 50, count: count, width: 1600)
        XCTAssertEqual(x4, x1 * 4, accuracy: 0.0001)
    }
}
