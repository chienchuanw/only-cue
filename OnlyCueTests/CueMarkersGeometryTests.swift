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
}
