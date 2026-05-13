import XCTest
@testable import OnlyCue

final class PlayheadInterpolatorTests: XCTestCase {

    func test_paused_returnsObservedTimeUnchanged() {
        let result = PlayheadInterpolator.renderedTime(
            observedTime: 12.0, observedAt: 100.0, now: 105.0, rate: 0, duration: 200
        )
        XCTAssertEqual(result, 12.0, accuracy: 1e-9)
    }

    func test_playingAtUnitRate_advancesByElapsedWallClock() {
        let result = PlayheadInterpolator.renderedTime(
            observedTime: 12.0, observedAt: 100.0, now: 100.25, rate: 1, duration: 200
        )
        XCTAssertEqual(result, 12.25, accuracy: 1e-9)
    }

    func test_playingAtDoubleRate_advancesTwiceAsFast() {
        let result = PlayheadInterpolator.renderedTime(
            observedTime: 12.0, observedAt: 100.0, now: 100.5, rate: 2, duration: 200
        )
        XCTAssertEqual(result, 13.0, accuracy: 1e-9)
    }

    func test_clampsToDuration() {
        let result = PlayheadInterpolator.renderedTime(
            observedTime: 199.9, observedAt: 100.0, now: 101.0, rate: 1, duration: 200
        )
        XCTAssertEqual(result, 200.0, accuracy: 1e-9)
    }

    func test_clampsToZeroAtReverseRate() {
        let result = PlayheadInterpolator.renderedTime(
            observedTime: 0.05, observedAt: 100.0, now: 100.5, rate: -1, duration: 200
        )
        XCTAssertEqual(result, 0.0, accuracy: 1e-9)
    }

    func test_negativeElapsed_isTreatedAsZero() {
        // Clock skew / stale sample: never let the playhead drift backwards.
        let result = PlayheadInterpolator.renderedTime(
            observedTime: 12.0, observedAt: 100.0, now: 99.0, rate: 1, duration: 200
        )
        XCTAssertEqual(result, 12.0, accuracy: 1e-9)
    }
}
