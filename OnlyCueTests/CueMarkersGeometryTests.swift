import XCTest
@testable import OnlyCue

final class CueMarkersGeometryTests: XCTestCase {

    func test_position_atZeroTime_isZero() {
        let x = CueMarkersGeometry.position(forTime: 0, width: 200, duration: 30)
        XCTAssertEqual(x, 0, accuracy: 0.001)
    }

    func test_position_atFullDuration_isWidth() {
        let x = CueMarkersGeometry.position(forTime: 30, width: 200, duration: 30)
        XCTAssertEqual(x, 200, accuracy: 0.001)
    }

    func test_position_isLinear() {
        let x = CueMarkersGeometry.position(forTime: 12, width: 200, duration: 30)
        XCTAssertEqual(x, 80, accuracy: 0.001)
    }

    func test_position_zeroDuration_returnsZero() {
        let x = CueMarkersGeometry.position(forTime: 5, width: 200, duration: 0)
        XCTAssertEqual(x, 0, accuracy: 0.001)
    }

    func test_time_addsDxAsFractionOfWidth() {
        let result = CueMarkersGeometry.time(originalTime: 12, dx: 50, width: 200, duration: 30)
        XCTAssertEqual(result, 19.5, accuracy: 0.001)
    }

    func test_time_clampsAtZero() {
        let result = CueMarkersGeometry.time(originalTime: 1, dx: -200, width: 200, duration: 30)
        XCTAssertEqual(result, 0, accuracy: 0.001)
    }

    func test_time_clampsAtDuration() {
        let result = CueMarkersGeometry.time(originalTime: 28, dx: 200, width: 200, duration: 30)
        XCTAssertEqual(result, 30, accuracy: 0.001)
    }

    // MARK: - time(forX:width:duration:)

    func test_timeForX_mapsLinearly() {
        let result = CueMarkersGeometry.time(forX: 50, width: 100, duration: 10)
        XCTAssertEqual(result, 5, accuracy: 1e-9)
    }

    func test_timeForX_clampsBelowZero() {
        let result = CueMarkersGeometry.time(forX: -20, width: 100, duration: 10)
        XCTAssertEqual(result, 0, accuracy: 1e-9)
    }

    func test_timeForX_clampsAboveDuration() {
        let result = CueMarkersGeometry.time(forX: 999, width: 100, duration: 10)
        XCTAssertEqual(result, 10, accuracy: 1e-9)
    }

    func test_timeForX_zeroWidth_returnsZero() {
        let result = CueMarkersGeometry.time(forX: 50, width: 0, duration: 10)
        XCTAssertEqual(result, 0, accuracy: 1e-9)
    }

    func test_positionAndTimeForX_areInverses() {
        let position = CueMarkersGeometry.position(forTime: 3.3, width: 240, duration: 12)
        let roundTrip = CueMarkersGeometry.time(forX: position, width: 240, duration: 12)
        XCTAssertEqual(roundTrip, 3.3, accuracy: 1e-6)
    }

    // MARK: - snapDeltaToBeat

    func test_snapDeltaToBeat_snapsAnchorToNearestBeat() {
        // 120 BPM => beats every 0.5s. Anchor at 1.0s. width=200px, duration=10s
        // => 20 px/s. Raw dx=+12px => proposed anchor time = 1.6s.
        // Nearest beat in [1.0, 1.5, 2.0, ...] is 1.5s. Adjusted dx = (1.5-1.0)*20 = +10px.
        let grid = DerivedTempoGrid(segments: [
            .init(startSeconds: 0, bpm: 120, beatsPerBar: 4)
        ])
        let adjusted = CueMarkersGeometry.snapDeltaToBeat(
            dxPixels: 12,
            anchorTime: 1.0,
            grid: grid,
            width: 200,
            duration: 10
        )
        XCTAssertEqual(adjusted, 10, accuracy: 0.001)
    }

    func test_snapDeltaToBeat_negativeDelta_snapsBackward() {
        // Same 120 BPM grid. Anchor at 2.0s. Raw dx=-6px => proposed = 1.7s.
        // Nearest beat is 1.5s. Adjusted dx = (1.5-2.0)*20 = -10px.
        let grid = DerivedTempoGrid(segments: [
            .init(startSeconds: 0, bpm: 120, beatsPerBar: 4)
        ])
        let adjusted = CueMarkersGeometry.snapDeltaToBeat(
            dxPixels: -6,
            anchorTime: 2.0,
            grid: grid,
            width: 200,
            duration: 10
        )
        XCTAssertEqual(adjusted, -10, accuracy: 0.001)
    }

    func test_snapDeltaToBeat_emptyGrid_returnsDxUnchanged() {
        let grid = DerivedTempoGrid(segments: [])
        let adjusted = CueMarkersGeometry.snapDeltaToBeat(
            dxPixels: 17,
            anchorTime: 2.0,
            grid: grid,
            width: 200,
            duration: 10
        )
        XCTAssertEqual(adjusted, 17, accuracy: 0.001)
    }

    func test_snapDeltaToBeat_zeroWidth_returnsDxUnchanged() {
        let grid = DerivedTempoGrid(segments: [
            .init(startSeconds: 0, bpm: 120, beatsPerBar: 4)
        ])
        let adjusted = CueMarkersGeometry.snapDeltaToBeat(
            dxPixels: 17,
            anchorTime: 2.0,
            grid: grid,
            width: 0,
            duration: 10
        )
        XCTAssertEqual(adjusted, 17, accuracy: 0.001)
    }

    // MARK: - spanWidth(forFade:at:width:duration:)

    func test_spanWidth_zeroFade_isZero() {
        let result = CueMarkersGeometry.spanWidth(forFade: 0, at: 5, width: 200, duration: 30)
        XCTAssertEqual(result, 0, accuracy: 0.001)
    }

    func test_spanWidth_fadeEqualsDuration_isFullWidth() {
        let result = CueMarkersGeometry.spanWidth(forFade: 30, at: 0, width: 200, duration: 30)
        XCTAssertEqual(result, 200, accuracy: 0.001)
    }

    func test_spanWidth_mapsLinearly() {
        // fade 3s of a 30s clip across 200px => 3/30 * 200 = 20px.
        let result = CueMarkersGeometry.spanWidth(forFade: 3, at: 5, width: 200, duration: 30)
        XCTAssertEqual(result, 20, accuracy: 0.001)
    }

    func test_spanWidth_overrunClampsToRightEdge() {
        // Cue at 28s with a 5s fade in a 30s clip: the band ends at 30s, not 33s,
        // so it spans (30-28)/30 * 200 = 13.333px, never past the content edge.
        let result = CueMarkersGeometry.spanWidth(forFade: 5, at: 28, width: 200, duration: 30)
        XCTAssertEqual(result, 200.0 * 2.0 / 30.0, accuracy: 0.001)
    }

    func test_spanWidth_zeroDuration_isZero() {
        let result = CueMarkersGeometry.spanWidth(forFade: 3, at: 5, width: 200, duration: 0)
        XCTAssertEqual(result, 0, accuracy: 0.001)
    }
}
