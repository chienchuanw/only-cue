import XCTest
@testable import OnlyCue

final class NudgeCueCommandTests: XCTestCase {

    func test_nudgeSelectedCueBack_notificationName_isStable() {
        XCTAssertEqual(
            Notification.Name.nudgeSelectedCueBack.rawValue,
            "OnlyCue.nudgeSelectedCueBack"
        )
    }

    func test_nudgeSelectedCueForward_notificationName_isStable() {
        XCTAssertEqual(
            Notification.Name.nudgeSelectedCueForward.rawValue,
            "OnlyCue.nudgeSelectedCueForward"
        )
    }
}
