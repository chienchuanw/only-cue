#if DEBUG
import XCTest
@testable import OnlyCue

final class UITestFirstLaunchHandlerTests: XCTestCase {

    func test_shouldForceFirstLaunch_withForceArgument_returnsTrue() {
        XCTAssertTrue(
            UITestFirstLaunchHandler.shouldForceFirstLaunch(
                arguments: ["OnlyCue", "--ui-test-first-launch=force"]
            )
        )
    }

    func test_shouldForceFirstLaunch_withSuppressArgument_returnsFalse() {
        XCTAssertFalse(
            UITestFirstLaunchHandler.shouldForceFirstLaunch(
                arguments: ["OnlyCue", "--ui-test-first-launch=suppress"]
            )
        )
    }

    func test_shouldForceFirstLaunch_withAbsentArgument_returnsFalse() {
        XCTAssertFalse(
            UITestFirstLaunchHandler.shouldForceFirstLaunch(
                arguments: ["OnlyCue", "--ui-test-seed=three-cues-1-3-6"]
            )
        )
    }

    func test_shouldForceFirstLaunch_withUnrecognizedValue_returnsFalse() {
        XCTAssertFalse(
            UITestFirstLaunchHandler.shouldForceFirstLaunch(
                arguments: ["OnlyCue", "--ui-test-first-launch=sometimes"]
            )
        )
    }
}
#endif
