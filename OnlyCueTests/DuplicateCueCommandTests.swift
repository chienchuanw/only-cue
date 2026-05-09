import XCTest
@testable import OnlyCue

final class DuplicateCueCommandTests: XCTestCase {

    func test_duplicateSelectedCueAtPlayhead_notificationName_isStable() {
        XCTAssertEqual(
            Notification.Name.duplicateSelectedCueAtPlayhead.rawValue,
            "OnlyCue.duplicateSelectedCueAtPlayhead"
        )
    }
}
