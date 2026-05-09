import XCTest
@testable import OnlyCue

final class ImportMediaCommandTests: XCTestCase {

    func test_importMediaRequested_notificationName_isStable() {
        XCTAssertEqual(
            Notification.Name.importMediaRequested.rawValue,
            "OnlyCue.importMediaRequested"
        )
    }
}
