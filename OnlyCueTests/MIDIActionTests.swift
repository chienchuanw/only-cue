import XCTest
@testable import OnlyCue

final class MIDIActionTests: XCTestCase {
    func test_discreteToken_roundTrips() {
        let action = MIDIAction.discrete(.playPause)
        XCTAssertEqual(action.token, "discrete:playPause")
        XCTAssertEqual(MIDIAction(token: action.token), action)
    }

    func test_continuousToken_roundTrips() {
        let action = MIDIAction.continuous(.scrub)
        XCTAssertEqual(action.token, "continuous:scrub")
        XCTAssertEqual(MIDIAction(token: action.token), action)
    }

    func test_badToken_returnsNil() {
        XCTAssertNil(MIDIAction(token: "discrete:notAnAction"))
        XCTAssertNil(MIDIAction(token: "continuous:zoom"))
        XCTAssertNil(MIDIAction(token: "bogus"))
    }

    func test_isContinuous() {
        XCTAssertTrue(MIDIAction.continuous(.ltcLevel).isContinuous)
        XCTAssertFalse(MIDIAction.discrete(.stepNextCue).isContinuous)
    }

    func test_codable_encodesAsTokenString() throws {
        let data = try JSONEncoder().encode(MIDIAction.continuous(.playbackRate))
        XCTAssertEqual(String(data: data, encoding: .utf8), "\"continuous:playbackRate\"")
        XCTAssertEqual(try JSONDecoder().decode(MIDIAction.self, from: data),
                       .continuous(.playbackRate))
    }
}
