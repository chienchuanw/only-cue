import XCTest
@testable import OnlyCue

final class FrontmostWindowGateTests: XCTestCase {

    func test_singleWindow_alwaysHandles() {
        // With one window open, `isKeyWindow` can be false transiently (a sheet
        // or a panel has key). Refusing then would make the menu look broken.
        XCTAssertTrue(WindowScope.shouldHandle(isFrontmost: false, openWindowCount: 1))
        XCTAssertTrue(WindowScope.shouldHandle(isFrontmost: true, openWindowCount: 1))
    }

    func test_multipleWindows_onlyTheFrontmostHandles() {
        XCTAssertTrue(WindowScope.shouldHandle(isFrontmost: true, openWindowCount: 2))
        XCTAssertFalse(WindowScope.shouldHandle(isFrontmost: false, openWindowCount: 2))
    }

    func test_zeroWindows_doesNotHandle() {
        XCTAssertFalse(WindowScope.shouldHandle(isFrontmost: false, openWindowCount: 0))
    }
}
