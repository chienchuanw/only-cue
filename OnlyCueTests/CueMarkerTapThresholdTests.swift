import XCTest
@testable import OnlyCue

/// #673 — the cue-marker tap-vs-drag classifier. A drag whose translation is
/// under the threshold is a tap (select + seek to the cue); at/over it is a
/// retime. The threshold was lowered 4→2pt so small drags retime instead of
/// being swallowed as a seek.
final class CueMarkerTapThresholdTests: XCTestCase {

    func test_belowThreshold_isTap() {
        XCTAssertTrue(CueMarkersOverlay.isTap(translationWidth: 0))
        XCTAssertTrue(CueMarkersOverlay.isTap(translationWidth: 1.9))
        XCTAssertTrue(CueMarkersOverlay.isTap(translationWidth: -1.5))
    }

    func test_atOrAboveThreshold_isDrag() {
        XCTAssertFalse(CueMarkersOverlay.isTap(translationWidth: 2))
        XCTAssertFalse(CueMarkersOverlay.isTap(translationWidth: 5))
        XCTAssertFalse(CueMarkersOverlay.isTap(translationWidth: -3))
    }
}
