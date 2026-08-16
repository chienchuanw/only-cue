import XCTest
@testable import OnlyCue

final class MiniPlaybackGateTests: XCTestCase {

    func test_handlesWhenMiniFrontmostAndMainNotKey() {
        XCTAssertTrue(MiniPlaybackGate.shouldHandle(panelVisible: true, isFrontmostMini: true, mainWindowIsKey: false))
    }

    func test_yieldsWhenMainWindowIsKey() {
        XCTAssertFalse(MiniPlaybackGate.shouldHandle(panelVisible: true, isFrontmostMini: true, mainWindowIsKey: true))
    }

    func test_yieldsWhenPanelHidden() {
        XCTAssertFalse(MiniPlaybackGate.shouldHandle(panelVisible: false, isFrontmostMini: true, mainWindowIsKey: false))
    }

    func test_yieldsWhenNotFrontmostMini() {
        XCTAssertFalse(MiniPlaybackGate.shouldHandle(panelVisible: true, isFrontmostMini: false, mainWindowIsKey: false))
    }
}
