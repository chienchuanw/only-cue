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
        let t = CueMarkersGeometry.time(originalTime: 12, dx: 50, width: 200, duration: 30)
        XCTAssertEqual(t, 19.5, accuracy: 0.001)
    }

    func test_time_clampsAtZero() {
        let t = CueMarkersGeometry.time(originalTime: 1, dx: -200, width: 200, duration: 30)
        XCTAssertEqual(t, 0, accuracy: 0.001)
    }

    func test_time_clampsAtDuration() {
        let t = CueMarkersGeometry.time(originalTime: 28, dx: 200, width: 200, duration: 30)
        XCTAssertEqual(t, 30, accuracy: 0.001)
    }
}
