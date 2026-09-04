import XCTest
@testable import OnlyCue

/// Wire-format unit tests for `MTCFrame` — the pure MIDI Timecode encoder
/// (epic #794). Every expectation here is a byte a receiver will actually see,
/// so these are the tests that decide whether a console locks.
final class MTCFrameTests: XCTestCase {

    // MARK: - Rate bits

    // MTC's rate field is two bits and encodes exactly 24 / 25 / 29.97-DF / 30.
    // There is no 30-fps-drop-frame code, so `fps30drop` takes the 29.97-DF slot
    // while still being clocked at 30 fps — the same simplification `LTCEncoder`
    // already ships (ADR-019, ADR-032).
    func test_rateBits_mapsEachSupportedFramerate() {
        XCTAssertEqual(MTCFrame.rateBits(for: .fps24), 0b00)
        XCTAssertEqual(MTCFrame.rateBits(for: .fps25), 0b01)
        XCTAssertEqual(MTCFrame.rateBits(for: .fps30drop), 0b10)
        XCTAssertEqual(MTCFrame.rateBits(for: .fps30), 0b11)
    }

    // MARK: - Quarter-frame data bytes

    // 01:02:03:04 @ 30 fps ND (rate bits 0b11).
    func test_quarterFrameByte_encodesEachPieceOfATimecode() throws {
        let timecode = try XCTUnwrap(Timecode(hours: 1, minutes: 2, seconds: 3, frames: 4, rate: .fps30))
        let expected: [UInt8] = [
            0x04,   // piece 0 — frames LSN  (4)
            0x10,   // piece 1 — frames MSN  (0)
            0x23,   // piece 2 — seconds LSN (3)
            0x30,   // piece 3 — seconds MSN (0)
            0x42,   // piece 4 — minutes LSN (2)
            0x50,   // piece 5 — minutes MSN (0)
            0x61,   // piece 6 — hours LSN   (1)
            0x76    // piece 7 — (rateBits << 1) | hours MSB = (0b11 << 1) | 0
        ]
        for piece in 0..<8 {
            XCTAssertEqual(
                MTCFrame.quarterFrameByte(piece: piece, timecode: timecode),
                expected[piece],
                "piece \(piece)"
            )
        }
    }

    // The maximum non-drop value — exercises every MSN field at once.
    func test_quarterFrameByte_encodesMaximumTimecode() throws {
        let timecode = try XCTUnwrap(Timecode(hours: 23, minutes: 59, seconds: 59, frames: 29, rate: .fps30))
        let expected: [UInt8] = [
            0x0D,   // frames  29 → LSN 0xD
            0x11,   // frames  29 → MSN 0x1
            0x2B,   // seconds 59 → LSN 0xB
            0x33,   // seconds 59 → MSN 0x3
            0x4B,   // minutes 59 → LSN 0xB
            0x53,   // minutes 59 → MSN 0x3
            0x67,   // hours   23 → LSN 0x7
            0x77    // (0b11 << 1) | (23 >> 4) = 0b110 | 1
        ]
        for piece in 0..<8 {
            XCTAssertEqual(
                MTCFrame.quarterFrameByte(piece: piece, timecode: timecode),
                expected[piece],
                "piece \(piece)"
            )
        }
    }

    // The piece index must occupy bits 4-6 of every data byte and never leak
    // into the payload nibble.
    func test_quarterFrameByte_carriesPieceIndexInHighNibble() throws {
        let timecode = try XCTUnwrap(Timecode(hours: 0, minutes: 0, seconds: 0, frames: 0, rate: .fps25))
        for piece in 0..<8 {
            let byte = MTCFrame.quarterFrameByte(piece: piece, timecode: timecode)
            XCTAssertEqual((byte >> 4) & 0x07, UInt8(piece), "piece index in byte \(byte)")
            XCTAssertEqual(byte & 0x80, 0, "data byte must never set the status bit")
        }
    }

    // Out-of-range piece indices are a programming error, not wire data — they
    // clamp into 0...7 rather than producing a byte with a bogus high nibble.
    func test_quarterFrameByte_clampsOutOfRangePiece() throws {
        let timecode = try XCTUnwrap(Timecode(hours: 1, minutes: 2, seconds: 3, frames: 4, rate: .fps30))
        XCTAssertEqual(MTCFrame.quarterFrameByte(piece: -1, timecode: timecode),
                       MTCFrame.quarterFrameByte(piece: 0, timecode: timecode))
        XCTAssertEqual(MTCFrame.quarterFrameByte(piece: 8, timecode: timecode),
                       MTCFrame.quarterFrameByte(piece: 7, timecode: timecode))
    }

    // MARK: - Quarter-frame messages

    func test_quarterFrameMessage_prefixesStatusByte() throws {
        let timecode = try XCTUnwrap(Timecode(hours: 1, minutes: 2, seconds: 3, frames: 4, rate: .fps30))
        XCTAssertEqual(MTCFrame.quarterFrameMessage(piece: 0, timecode: timecode), [0xF1, 0x04])
        XCTAssertEqual(MTCFrame.quarterFrameMessage(piece: 7, timecode: timecode), [0xF1, 0x76])
    }

    // MARK: - Full Frame

    func test_fullFrameBytes_wrapsTimecodeInUniversalRealTimeSysEx() throws {
        let timecode = try XCTUnwrap(Timecode(hours: 1, minutes: 2, seconds: 3, frames: 4, rate: .fps30))
        // F0 7F <device> 01 01 hh mm ss ff F7, hh = (rateBits << 5) | hours.
        XCTAssertEqual(MTCFrame.fullFrameBytes(timecode),
                       [0xF0, 0x7F, 0x7F, 0x01, 0x01, 0x61, 0x02, 0x03, 0x04, 0xF7])
    }

    func test_fullFrameBytes_packsRateBitsAboveHours() throws {
        let at25 = try XCTUnwrap(Timecode(hours: 10, minutes: 20, seconds: 30, frames: 24, rate: .fps25))
        XCTAssertEqual(MTCFrame.fullFrameBytes(at25),
                       [0xF0, 0x7F, 0x7F, 0x01, 0x01, 0x2A, 0x14, 0x1E, 0x18, 0xF7])

        let at24 = try XCTUnwrap(Timecode(hours: 23, minutes: 0, seconds: 0, frames: 23, rate: .fps24))
        XCTAssertEqual(MTCFrame.fullFrameBytes(at24),
                       [0xF0, 0x7F, 0x7F, 0x01, 0x01, 0x17, 0x00, 0x00, 0x17, 0xF7])
    }

    // Drop-frame labels ride through unchanged — only the rate bits mark them.
    func test_fullFrameBytes_dropFrameUsesTheNineteenNinetySevenSlot() throws {
        let timecode = try XCTUnwrap(Timecode(hours: 0, minutes: 1, seconds: 0, frames: 2, rate: .fps30drop))
        XCTAssertEqual(MTCFrame.fullFrameBytes(timecode),
                       [0xF0, 0x7F, 0x7F, 0x01, 0x01, 0x40, 0x01, 0x00, 0x02, 0xF7])
    }
}
