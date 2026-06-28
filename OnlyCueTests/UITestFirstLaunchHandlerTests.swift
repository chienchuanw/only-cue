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

    func test_shouldSuppressForSeed_withSeed_returnsTrue() {
        XCTAssertTrue(
            UITestFirstLaunchHandler.shouldSuppressForSeed(
                arguments: ["OnlyCue", "--ui-test-seed=set-list-act-i"]
            )
        )
    }

    func test_shouldSuppressForSeed_withSeedButForced_returnsFalse() {
        XCTAssertFalse(
            UITestFirstLaunchHandler.shouldSuppressForSeed(
                arguments: ["OnlyCue", "--ui-test-seed=set-list-act-i", "--ui-test-first-launch=force"]
            )
        )
    }

    func test_shouldSuppressForSeed_withoutSeed_returnsFalse() {
        XCTAssertFalse(
            UITestFirstLaunchHandler.shouldSuppressForSeed(
                arguments: ["OnlyCue", "--ui-test-first-launch=force"]
            )
        )
    }

    func test_shouldSuppressForSeed_withNoArguments_returnsFalse() {
        XCTAssertFalse(
            UITestFirstLaunchHandler.shouldSuppressForSeed(arguments: ["OnlyCue"])
        )
    }

    func test_shouldSuppress_withSuppressArgument_returnsTrue() {
        XCTAssertTrue(
            UITestFirstLaunchHandler.shouldSuppress(
                arguments: ["OnlyCue", "--ui-test-first-launch=suppress"]
            )
        )
    }

    func test_shouldSuppress_withSeed_returnsTrue() {
        XCTAssertTrue(
            UITestFirstLaunchHandler.shouldSuppress(
                arguments: ["OnlyCue", "--ui-test-seed=three-cues-1-3-6"]
            )
        )
    }

    func test_shouldSuppress_withSeedButForced_returnsFalse() {
        XCTAssertFalse(
            UITestFirstLaunchHandler.shouldSuppress(
                arguments: ["OnlyCue", "--ui-test-seed=three-cues-1-3-6", "--ui-test-first-launch=force"]
            )
        )
    }

    func test_shouldSuppress_withNoSuppressSignal_returnsFalse() {
        XCTAssertFalse(
            UITestFirstLaunchHandler.shouldSuppress(arguments: ["OnlyCue"])
        )
    }
}
#endif
