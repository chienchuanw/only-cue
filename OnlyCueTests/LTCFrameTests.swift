import XCTest
@testable import OnlyCue

/// Coverage for the SMPTE LTC 80-bit frame (`LTCFrame`) and the biphase-mark
/// modulation primitive (`LTCBiphaseEncoder`) — epic #33 leaf 2 (and the
/// encoder portion of leaf 7's tests).
final class LTCFrameTests: XCTestCase {

    private func tc(_ hour: Int, _ minute: Int, _ second: Int, _ frame: Int, _ rate: SMPTEFramerate = .fps30) throws -> Timecode {
        try XCTUnwrap(Timecode(hours: hour, minutes: minute, seconds: second, frames: frame, rate: rate))
    }

    // MARK: - LTCFrame structure

    func test_frame_is80Bits() throws {
        XCTAssertEqual(LTCFrame(timecode: try tc(0, 0, 0, 0)).bits.count, 80)
    }

    func test_frame_encodesAndDecodesTimecodeComponents() throws {
        let frame = LTCFrame(timecode: try tc(12, 34, 56, 23, .fps30))
        XCTAssertEqual(frame.hours, 12)
        XCTAssertEqual(frame.minutes, 34)
        XCTAssertEqual(frame.seconds, 56)
        XCTAssertEqual(frame.frames, 23)
    }

    func test_frame_componentsRoundTrip_forSeveralTimecodes() throws {
        let cases: [Timecode] = [
            try tc(0, 0, 0, 0, .fps24), try tc(1, 2, 3, 4, .fps25), try tc(23, 59, 59, 29, .fps30),
            try tc(10, 20, 30, 15, .fps30drop), try tc(9, 0, 8, 7, .fps24)
        ]
        for original in cases {
            let ltc = LTCFrame(timecode: original)
            XCTAssertEqual(
                [ltc.hours, ltc.minutes, ltc.seconds, ltc.frames],
                [original.hours, original.minutes, original.seconds, original.frames],
                "\(original.displayString)"
            )
        }
    }

    func test_frame_dropFrameFlag_tracksRate() throws {
        XCTAssertTrue(LTCFrame(timecode: try tc(0, 1, 2, 3, .fps30drop)).bits[10])
        XCTAssertFalse(LTCFrame(timecode: try tc(0, 1, 2, 3, .fps30)).bits[10])
        XCTAssertFalse(LTCFrame(timecode: try tc(0, 1, 2, 3, .fps25)).bits[10])
    }

    func test_frame_syncWord_isFixedPattern() throws {
        let frame = LTCFrame(timecode: try tc(7, 8, 9, 10))
        XCTAssertTrue(frame.syncWordIsValid)
        let expected = [false, false] + Array(repeating: true, count: 12) + [false, true]
        XCTAssertEqual(Array(frame.bits[64..<80]), expected)
        XCTAssertEqual(LTCFrame.syncWord, expected)
    }

    func test_frame_userAndFlagBits_areZero() throws {
        let frame = LTCFrame(timecode: try tc(12, 34, 56, 7, .fps30))
        let userBitRanges = [4..<8, 12..<16, 20..<24, 28..<32, 36..<40, 44..<48, 52..<56, 59..<63]
        for range in userBitRanges {
            XCTAssertTrue(frame.bits[range].allSatisfy { !$0 }, "user bits \(range) should be zero")
        }
        XCTAssertFalse(frame.bits[11], "colour-frame flag should be zero")
        XCTAssertFalse(frame.bits[43], "binary-group-flag bit should be zero")
        XCTAssertFalse(frame.bits[58], "binary-group-flag bit should be zero")
        XCTAssertFalse(frame.bits[63], "binary-group-flag bit should be zero")
    }

    // MARK: - Parity (bit-polarity correction)

    func test_frame_hasEvenParity_always() throws {
        for hour in [0, 1, 12, 23] {
            for frame in [0, 1, 7, 13, 23, 29] {
                XCTAssertTrue(LTCFrame(timecode: try tc(hour, 33, 44, frame, .fps30)).hasEvenParity, "\(hour):\(frame)")
            }
        }
        XCTAssertTrue(LTCFrame(timecode: try tc(10, 20, 30, 15, .fps30drop)).hasEvenParity)
        XCTAssertTrue(LTCFrame(timecode: try tc(1, 2, 3, 4, .fps25)).hasEvenParity)
    }

    func test_frame_parityBit27_isTheOnlyBitUsedForCorrection() throws {
        for value in [[0, 0, 0, 1], [12, 34, 56, 23], [23, 59, 59, 29], [1, 11, 0, 0]] {
            let frame = LTCFrame(timecode: try tc(value[0], value[1], value[2], value[3], .fps30))
            var withoutParity = frame.bits
            withoutParity[LTCFrame.parityBitIndex] = false
            let oddWithoutParity = !withoutParity.lazy.filter { $0 }.count.isMultiple(of: 2)
            XCTAssertEqual(frame.bits[LTCFrame.parityBitIndex], oddWithoutParity, "\(value)")
        }
    }

    /// #853 — SMPTE 12M moves the bi-phase mark phase-correction bit to **59**
    /// at 25 fps; bit 27 is BGF0 there. Writing the correction at 27 raises a
    /// flag a conforming reader acts on *and* leaves the real parity position
    /// clear, so the word can go out with odd parity.
    ///
    /// Each of these 25 fps values has an odd number of ones before correction
    /// (the sync word alone contributes 13), so the bit must actually be set —
    /// otherwise the test would pass on a frame that never needed correcting.
    func test_frame_at25fps_writesCorrectionAtBit59_notBit27() throws {
        for value in [[0, 0, 0, 0], [12, 34, 56, 7], [9, 0, 8, 7], [0, 1, 0, 2]] {
            let frame = LTCFrame(timecode: try tc(value[0], value[1], value[2], value[3], .fps25))
            XCTAssertTrue(frame.bits[59], "\(value): 25 fps carries the correction at bit 59")
            XCTAssertFalse(frame.bits[27], "\(value): bit 27 is BGF0 at 25 fps and must stay clear")
            XCTAssertTrue(frame.hasEvenParity, "\(value)")
        }
    }

    /// The other half of #853: when the word is already even, *neither* candidate
    /// position may be set. Without this, an implementation that simply set bit
    /// 59 unconditionally would pass the test above.
    func test_frame_at25fps_leavesBothPositionsClear_whenNoCorrectionIsNeeded() throws {
        for value in [[1, 2, 3, 4], [23, 59, 59, 24], [17, 30, 45, 12]] {
            let frame = LTCFrame(timecode: try tc(value[0], value[1], value[2], value[3], .fps25))
            XCTAssertFalse(frame.bits[59], "\(value): no correction needed, bit 59 stays clear")
            XCTAssertFalse(frame.bits[27], "\(value): no correction needed, bit 27 stays clear")
            XCTAssertTrue(frame.hasEvenParity, "\(value)")
        }
    }

    /// #853 — and the converse: at 24 / 30 fps bit 59 is BGF2 and must never be
    /// used for correction, whichever way the parity falls.
    func test_frame_at24And30fps_neverWritesBit59() throws {
        for rate in [SMPTEFramerate.fps24, .fps30, .fps30drop] {
            // `01:11:00:02` rather than `…:00` — at 30df frames 00 and 01 are
            // skipped at the top of every minute but the tenth, so `01:11:00:00`
            // is not a timecode at all and `tc` would fail to unwrap it.
            for value in [[0, 0, 0, 1], [12, 34, 56, 7], [23, 59, 59, 23], [1, 11, 0, 2]] {
                let frame = LTCFrame(timecode: try tc(value[0], value[1], value[2], value[3], rate))
                XCTAssertFalse(frame.bits[59], "\(rate.rawValue) \(value): bit 59 is BGF2 outside 25 fps")
                XCTAssertTrue(frame.hasEvenParity, "\(rate.rawValue) \(value)")
            }
        }
    }

    // MARK: - LTCBiphaseEncoder

    func test_biphase_zeroBit_transitionsOnlyAtBoundary() {
        let (samples, end) = LTCBiphaseEncoder.levels(for: [false, false], samplesPerHalfBit: 1, startLevel: false)
        XCTAssertEqual(samples, [true, true, false, false])
        XCTAssertEqual(end, false)
    }

    func test_biphase_oneBit_addsMidBitTransition() {
        let (one, _) = LTCBiphaseEncoder.levels(for: [true], samplesPerHalfBit: 1, startLevel: false)
        XCTAssertEqual(one, [true, false])
        let (oneOne, end) = LTCBiphaseEncoder.levels(for: [true, true], samplesPerHalfBit: 1, startLevel: false)
        XCTAssertEqual(oneOne, [true, false, true, false])
        XCTAssertEqual(end, false)
    }

    func test_biphase_sampleCount_isTwoTimesBitsTimesSamplesPerHalfBit() throws {
        let frame = LTCFrame(timecode: try tc(0, 0, 0, 0))
        let (samples, _) = LTCBiphaseEncoder.levels(for: frame.bits, samplesPerHalfBit: 10)
        XCTAssertEqual(samples.count, 80 * 2 * 10)
    }

    func test_biphase_samplesPerHalfBit_scalesEachHalfBit() {
        let (samples, _) = LTCBiphaseEncoder.levels(for: [true], samplesPerHalfBit: 3, startLevel: false)
        XCTAssertEqual(samples, [true, true, true, false, false, false])
    }

    func test_biphase_endLevel_chainsAcrossCalls() {
        let bitsA: [Bool] = [true, false, true]
        let bitsB: [Bool] = [false, true]
        let (combinedDirect, _) = LTCBiphaseEncoder.levels(for: bitsA + bitsB, samplesPerHalfBit: 2)
        let (firstSamples, mid) = LTCBiphaseEncoder.levels(for: bitsA, samplesPerHalfBit: 2)
        let (secondSamples, _) = LTCBiphaseEncoder.levels(for: bitsB, samplesPerHalfBit: 2, startLevel: mid)
        XCTAssertEqual(firstSamples + secondSamples, combinedDirect)
    }

    func test_biphase_startLevelHigh_invertsTheWholeStream() {
        let (low, _) = LTCBiphaseEncoder.levels(for: [true, false], samplesPerHalfBit: 1, startLevel: false)
        let (high, _) = LTCBiphaseEncoder.levels(for: [true, false], samplesPerHalfBit: 1, startLevel: true)
        XCTAssertEqual(high, low.map { !$0 })
    }
}
