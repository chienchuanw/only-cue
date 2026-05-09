import XCTest
@testable import OnlyCue

final class SnapCueCommandTests: XCTestCase {

    func test_snapSelectedCueToPlayhead_notificationName_isStable() {
        XCTAssertEqual(
            Notification.Name.snapSelectedCueToPlayhead.rawValue,
            "OnlyCue.snapSelectedCueToPlayhead"
        )
    }
}
