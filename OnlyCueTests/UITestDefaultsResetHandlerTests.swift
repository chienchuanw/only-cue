#if DEBUG
import XCTest
@testable import OnlyCue

final class UITestDefaultsResetHandlerTests: XCTestCase {

    func test_isResetRequested_withResetArgument_returnsTrue() {
        XCTAssertTrue(
            UITestDefaultsResetHandler.isResetRequested(
                arguments: ["OnlyCue", "--ui-test-reset"],
                ciMarkerPresent: false
            )
        )
    }

    func test_isResetRequested_withAnyUITestArgument_returnsTrue() {
        XCTAssertTrue(
            UITestDefaultsResetHandler.isResetRequested(
                arguments: ["OnlyCue", "--ui-test-seed=three-cues-1-3-6"],
                ciMarkerPresent: false
            )
        )
    }

    func test_isResetRequested_withCIMarkerOnly_returnsTrue() {
        XCTAssertTrue(
            UITestDefaultsResetHandler.isResetRequested(
                arguments: ["OnlyCue"],
                ciMarkerPresent: true
            )
        )
    }

    func test_isResetRequested_plainLaunchNoMarker_returnsFalse() {
        XCTAssertFalse(
            UITestDefaultsResetHandler.isResetRequested(
                arguments: ["OnlyCue"],
                ciMarkerPresent: false
            )
        )
    }
}
#endif
