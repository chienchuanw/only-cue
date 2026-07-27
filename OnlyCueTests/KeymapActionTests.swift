import XCTest
@testable import OnlyCue

final class KeymapActionTests: XCTestCase {
    func test_goAndStop_exist_withStableRawValues() {
        XCTAssertEqual(KeymapAction(rawValue: "go"), .go)
        XCTAssertEqual(KeymapAction(rawValue: "stop"), .stop)
    }

    func test_goAndStop_haveDisplayNames() {
        XCTAssertEqual(KeymapAction.go.displayName, "Go")
        XCTAssertEqual(KeymapAction.stop.displayName, "Stop")
    }

    func test_defaultKeymap_isTotalOverAllActions() {
        // Every action (incl. the new two) resolves to its default chord, so the
        // map stays total and the settings table has no phantom fallback chords.
        let map = Keymap.default
        for action in KeymapAction.allCases {
            XCTAssertNotNil(Keymap.defaultBindings[action], "missing default for \(action.rawValue)")
            _ = map.chord(for: action)
        }
    }
}
