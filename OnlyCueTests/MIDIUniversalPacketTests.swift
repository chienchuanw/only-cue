import XCTest
@testable import OnlyCue

/// `MIDIUniversalPacket` converts MIDI 1.0 byte messages into the Universal MIDI
/// Packet words `MIDISendEventList` wants (epic #794).
///
/// This exists so the riskiest part of the send path — bit-packing a status byte
/// and a SysEx payload into 32-bit words — is pure and pinned by tests, leaving
/// `MTCOutput` as a thin edge that only opens a port and hands over words. It is
/// the write-side counterpart of the UMP *parsing* `MIDIInput` already does.
final class MIDIUniversalPacketTests: XCTestCase {

    // MARK: - System Common

    // Message type 0x1 (System Real Time / Common), group 0:
    // [0x1|group][status][data1][data2].
    func test_systemCommonWord_packsStatusAndData() {
        XCTAssertEqual(
            MIDIUniversalPacket.systemCommonWord(status: 0xF1, data1: 0x04, data2: 0x00),
            0x10F1_0400
        )
        XCTAssertEqual(
            MIDIUniversalPacket.systemCommonWord(status: 0xF1, data1: 0x76, data2: 0x00),
            0x10F1_7600
        )
    }

    func test_systemCommonWord_honoursTheGroupNibble() {
        XCTAssertEqual(
            MIDIUniversalPacket.systemCommonWord(status: 0xF1, data1: 0x04, data2: 0x00, group: 5),
            0x15F1_0400
        )
        // Only four bits of group exist — a larger value must not bleed into the
        // message-type nibble.
        XCTAssertEqual(
            MIDIUniversalPacket.systemCommonWord(status: 0xF1, data1: 0x00, data2: 0x00, group: 0xFF),
            0x1FF1_0000
        )
    }

    // MARK: - SysEx7

    // A payload of six bytes or fewer is a single "complete" packet (status 0).
    func test_sysEx7Words_shortPayloadIsOneCompletePacket() {
        let words = MIDIUniversalPacket.sysEx7Words(payload: [0x7F, 0x01, 0x02])
        XCTAssertEqual(words, [0x3003_7F01, 0x0200_0000])
    }

    func test_sysEx7Words_exactlySixBytesStillFitsOnePacket() {
        let words = MIDIUniversalPacket.sysEx7Words(payload: [0x01, 0x02, 0x03, 0x04, 0x05, 0x06])
        XCTAssertEqual(words, [0x3006_0102, 0x0304_0506])
    }

    // The MTC Full Frame payload (everything between F0 and F7) is eight bytes,
    // so it splits into a start packet and an end packet.
    func test_sysEx7Words_fullFramePayloadSplitsIntoStartAndEnd() {
        let payload: [UInt8] = [0x7F, 0x7F, 0x01, 0x01, 0x61, 0x02, 0x03, 0x04]
        XCTAssertEqual(
            MIDIUniversalPacket.sysEx7Words(payload: payload),
            [
                0x3016_7F7F, 0x0101_6102,   // start, 6 bytes
                0x3032_0304, 0x0000_0000    // end, 2 bytes
            ]
        )
    }

    // A payload spanning three packets must use start / continue / end, since a
    // receiver keys on those to reassemble.
    func test_sysEx7Words_longPayloadUsesContinuePackets() {
        let payload = [UInt8](0x01...0x0E)   // 14 bytes → 6 + 6 + 2
        let words = MIDIUniversalPacket.sysEx7Words(payload: payload)

        XCTAssertEqual(words.count, 6)
        XCTAssertEqual((words[0] >> 20) & 0x0F, 0x1, "first packet is start")
        XCTAssertEqual((words[2] >> 20) & 0x0F, 0x2, "middle packet is continue")
        XCTAssertEqual((words[4] >> 20) & 0x0F, 0x3, "last packet is end")
        XCTAssertEqual((words[4] >> 16) & 0x0F, 2, "last packet carries 2 bytes")
    }

    func test_sysEx7Words_emptyPayloadProducesNothing() {
        XCTAssertTrue(MIDIUniversalPacket.sysEx7Words(payload: []).isEmpty)
    }

    // Callers pass raw MTC bytes; the F0/F7 framing belongs to the byte stream,
    // not to UMP, so it is stripped rather than transmitted as payload.
    func test_sysEx7Words_stripsSysExFramingBytes() {
        let framed: [UInt8] = [0xF0, 0x7F, 0x01, 0x02, 0xF7]
        XCTAssertEqual(
            MIDIUniversalPacket.sysEx7Words(payload: framed),
            MIDIUniversalPacket.sysEx7Words(payload: [0x7F, 0x01, 0x02])
        )
    }
}
