#if DEBUG
import XCTest
@testable import OnlyCue

final class UITestDefaultsResetHandlerTests: XCTestCase {

    func test_isResetRequested_withResetArgument_returnsTrue() {
        XCTAssertTrue(
            UITestDefaultsResetHandler.isResetRequested(
                arguments: ["OnlyCue", "--ui-test-reset"]
            )
        )
    }

    func test_isResetRequested_withAnyUITestArgument_returnsTrue() {
        XCTAssertTrue(
            UITestDefaultsResetHandler.isResetRequested(
                arguments: ["OnlyCue", "--ui-test-seed=three-cues-1-3-6"]
            )
        )
    }

    // A plain launch with no `--ui-test*` argument must not reset. Previously a
    // CI marker file could force a reset here (#792); that path is gone, so the
    // decision now rests entirely on the launch arguments.
    func test_isResetRequested_plainLaunch_returnsFalse() {
        XCTAssertFalse(
            UITestDefaultsResetHandler.isResetRequested(
                arguments: ["OnlyCue"]
            )
        )
    }

    func test_isResetRequested_withUnrelatedArgument_returnsFalse() {
        XCTAssertFalse(
            UITestDefaultsResetHandler.isResetRequested(
                arguments: ["OnlyCue", "-ApplePersistenceIgnoreState", "YES"]
            )
        )
    }
}
#endif
