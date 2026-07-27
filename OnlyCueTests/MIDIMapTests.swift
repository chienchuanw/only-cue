import XCTest
@testable import OnlyCue

final class MIDIMapTests: XCTestCase {
    private let cc45 = MIDIControlID(channel: 1, kind: .cc, number: 45)
    private let note60 = MIDIControlID(channel: 1, kind: .note, number: 60)

    func test_default_isEmpty() {
        XCTAssertNil(MIDIMap.default.action(for: cc45))
    }

    func test_learn_thenLookup() {
        var map = MIDIMap.default
        map.learn(cc45, as: .discrete(.playPause))
        XCTAssertEqual(map.action(for: cc45), .discrete(.playPause))
    }

    func test_learn_sameControlReassigns() {
        var map = MIDIMap.default
        map.learn(cc45, as: .discrete(.playPause))
        map.learn(cc45, as: .continuous(.scrub))
        XCTAssertEqual(map.action(for: cc45), .continuous(.scrub))
    }

    func test_twoControlsMayShareAnAction() {
        var map = MIDIMap.default
        map.learn(cc45, as: .discrete(.playPause))
        map.learn(note60, as: .discrete(.playPause))
        XCTAssertEqual(Set(map.controls(for: .discrete(.playPause))), [cc45, note60])
    }

    func test_clear_removesBinding() {
        var map = MIDIMap.default
        map.learn(cc45, as: .discrete(.playPause))
        map.clear(cc45)
        XCTAssertNil(map.action(for: cc45))
    }

    func test_encode_decode_roundTrips() throws {
        var map = MIDIMap.default
        map.learn(cc45, as: .continuous(.scrub))
        map.learn(note60, as: .discrete(.stepNextCue))
        XCTAssertEqual(MIDIMap.decode(try map.encoded()), map)
    }

    func test_decode_nilOrCorrupt_isEmpty() {
        XCTAssertEqual(MIDIMap.decode(nil), .default)
        XCTAssertEqual(MIDIMap.decode(Data("garbage".utf8)), .default)
    }

    func test_decode_dropsUnknownTokens() throws {
        // A stored map with one good and one bogus entry keeps only the good one.
        let json = #"{"cc:1:45":"continuous:scrub","bogus":"discrete:playPause","note:1:60":"continuous:zoom"}"#
        let map = MIDIMap.decode(Data(json.utf8))
        XCTAssertEqual(map.action(for: cc45), .continuous(.scrub))
        XCTAssertNil(map.action(for: note60))   // "continuous:zoom" is not a valid action
    }
}
