import XCTest
@testable import OnlyCue

final class MIDIMessageTests: XCTestCase {
    func test_parse_noteOn_decodesChannelNumberVelocity() {
        // 0x90 = Note On, channel 0 (→ 1-based 1); note 60; velocity 100.
        XCTAssertEqual(MIDIMessage.parse([0x90, 60, 100]),
                       .note(channel: 1, number: 60, velocity: 100))
    }

    func test_parse_noteOff_becomesZeroVelocityNote() {
        // 0x82 = Note Off, channel 2 (→ 3); any release velocity → 0.
        XCTAssertEqual(MIDIMessage.parse([0x82, 60, 40]),
                       .note(channel: 3, number: 60, velocity: 0))
    }

    func test_parse_noteOnWithZeroVelocity_isZeroVelocityNote() {
        // Running-status "note off": Note On, velocity 0.
        XCTAssertEqual(MIDIMessage.parse([0x90, 60, 0]),
                       .note(channel: 1, number: 60, velocity: 0))
    }

    func test_parse_controlChange_decodesChannelNumberValue() {
        // 0xB0 = CC, channel 0 (→ 1); controller 45; value 127.
        XCTAssertEqual(MIDIMessage.parse([0xB0, 45, 127]),
                       .controlChange(channel: 1, number: 45, value: 127))
    }

    func test_parse_unsupportedStatus_returnsNil() {
        XCTAssertNil(MIDIMessage.parse([0xE0, 0, 64]))   // pitch bend
        XCTAssertNil(MIDIMessage.parse([0xC0, 5]))       // program change
    }

    func test_parse_truncated_returnsNil() {
        XCTAssertNil(MIDIMessage.parse([0x90, 60]))      // missing velocity
        XCTAssertNil(MIDIMessage.parse([]))              // empty
    }
}
