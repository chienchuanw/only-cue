import XCTest
@testable import OnlyCue

@MainActor
final class FirstLaunchHintTrackerTests: XCTestCase {

    override func setUp() {
        super.setUp()
        FirstLaunchHintTracker.shared.resetForTesting()
    }

    func test_startsUnshown() {
        XCTAssertFalse(FirstLaunchHintTracker.shared.hasShownWaveformZoomHint)
    }

    func test_markShown_flipsFlag() {
        FirstLaunchHintTracker.shared.markShown()
        XCTAssertTrue(FirstLaunchHintTracker.shared.hasShownWaveformZoomHint)
    }

    func test_markShown_isIdempotent() {
        FirstLaunchHintTracker.shared.markShown()
        FirstLaunchHintTracker.shared.markShown()
        XCTAssertTrue(
            FirstLaunchHintTracker.shared.hasShownWaveformZoomHint,
            "repeat markShown calls must not flip the flag back — session-scoped means once-true-stays-true"
        )
    }
}
