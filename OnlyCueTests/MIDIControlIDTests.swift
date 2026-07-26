import XCTest
@testable import OnlyCue

final class MIDIControlIDTests: XCTestCase {
    func test_initFromNote_isNoteKind() {
        let id = MIDIControlID(message: .note(channel: 1, number: 60, velocity: 100))
        XCTAssertEqual(id, MIDIControlID(channel: 1, kind: .note, number: 60))
    }

    func test_initFromCC_isCCKind_ignoringValue() {
        let id = MIDIControlID(message: .controlChange(channel: 2, number: 45, value: 0))
        XCTAssertEqual(id, MIDIControlID(channel: 2, kind: .cc, number: 45))
    }

    func test_token_roundTrips() {
        let id = MIDIControlID(channel: 3, kind: .cc, number: 7)
        XCTAssertEqual(id.token, "cc:3:7")
        XCTAssertEqual(MIDIControlID(token: id.token), id)
    }

    func test_initFromBadToken_returnsNil() {
        XCTAssertNil(MIDIControlID(token: "cc:3"))
        XCTAssertNil(MIDIControlID(token: "pitch:1:1"))
        XCTAssertNil(MIDIControlID(token: "cc:x:1"))
    }
}
