import XCTest
@testable import OnlyCue

final class CueListHeaderTests: XCTestCase {

    /// Pins the public accessibility identifier used by the header row above
    /// the cue list. UI tests look this up; if it drifts, fail loud.
    func test_cueListHeader_accessibilityIdentifier_isStable() {
        XCTAssertEqual(CueListPane.headerAccessibilityIdentifier, "cueListHeader")
    }
}
