import XCTest
@testable import OnlyCue

// The generator + drift guard for `golden/mtc-wire-v1.json`. The contract model
// and the case matrix live in `MTCWireGolden.swift`.

extension MTCWireGolden {

    private static func rateBitsCase(_ rate: SMPTEFramerate) -> MTCWireGoldenVector.Case {
        MTCWireGoldenVector.Case(
            label: "rateBits/\(rate.rawValue)",
            op: "rateBits",
            rate: rate.rawValue,
            input: MTCWireGoldenVector.Input(),
            expect: MTCWireGoldenVector.Expect(byte: Int(MTCFrame.rateBits(for: rate)))
        )
    }

    private static func input(_ timecode: Timecode, piece: Int? = nil) -> MTCWireGoldenVector.Input {
        MTCWireGoldenVector.Input(
            hours: timecode.hours,
            minutes: timecode.minutes,
            seconds: timecode.seconds,
            frames: timecode.frames,
            piece: piece
        )
    }

    /// The whole eight-message sequence as bytes on the wire — `F1 <data>` × 8 —
    /// so the status byte and the piece ordering are pinned alongside the
    /// payload nibbles.
    private static func sequenceCase(_ timecode: Timecode) -> MTCWireGoldenVector.Case {
        let bytes = (0..<MTCFrame.piecesPerTimecode).flatMap { piece in
            MTCFrame.quarterFrameMessage(piece: piece, timecode: timecode)
        }
        return MTCWireGoldenVector.Case(
            label: "quarterFrameSequence/\(timecode.rate.rawValue)/\(timecode.displayString)",
            op: "quarterFrameSequence",
            rate: timecode.rate.rawValue,
            input: input(timecode),
            expect: MTCWireGoldenVector.Expect(bytes: bytes.map(Int.init))
        )
    }

    private static func fullFrameCase(_ timecode: Timecode) -> MTCWireGoldenVector.Case {
        MTCWireGoldenVector.Case(
            label: "fullFrame/\(timecode.rate.rawValue)/\(timecode.displayString)",
            op: "fullFrame",
            rate: timecode.rate.rawValue,
            input: input(timecode),
            expect: MTCWireGoldenVector.Expect(bytes: MTCFrame.fullFrameBytes(timecode).map(Int.init))
        )
    }

    private static func clampCase(_ timecode: Timecode, piece: Int) -> MTCWireGoldenVector.Case {
        MTCWireGoldenVector.Case(
            label: "quarterFrame/\(timecode.rate.rawValue)/\(timecode.displayString)/piece\(piece)",
            op: "quarterFrame",
            rate: timecode.rate.rawValue,
            input: input(timecode, piece: piece),
            expect: MTCWireGoldenVector.Expect(
                byte: Int(MTCFrame.quarterFrameByte(piece: piece, timecode: timecode))
            )
        )
    }

    static func make() throws -> MTCWireGoldenVector {
        var cases = allRates.map(rateBitsCase)
        for rate in allRates {
            let timecodes = try timecodeInputs(for: rate).map { try timecode($0, rate: rate) }
            cases += timecodes.map(sequenceCase)
            cases += timecodes.map(fullFrameCase)
            // The clamp is rate-independent, but piece 7 carries the rate bits,
            // so pin it at every rate rather than only one.
            if let last = timecodes.last {
                cases += clampedPieces.map { clampCase(last, piece: $0) }
            }
        }
        return MTCWireGoldenVector(
            contract: "mtc-wire",
            version: 1,
            note: "macOS-generated golden vectors for the OnlyCue MTC wire format (rate "
                + "bits, quarter-frame messages, and the Full Frame SysEx). The C# "
                + "OnlyCue.Core re-implementation must reproduce every case exactly. "
                + "To regenerate after a deliberate MTCFrame change, delete "
                + "golden/mtc-wire-v1.json and re-run the test suite.",
            cases: cases
        )
    }

    /// Deterministic encoding so the committed file is stable and diff-friendly.
    static func encoded(_ vector: MTCWireGoldenVector) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(vector)
    }
}

// MARK: - Tests

final class MTCWireGoldenVectorTests: XCTestCase {

    private func goldenURL() throws -> URL {
        try repoRoot().appendingPathComponent("golden", isDirectory: true)
            .appendingPathComponent("mtc-wire-v1.json")
    }

    /// Independent pins, hand-computed from the MTC spec rather than read off
    /// the implementation — so a wrong `MTCFrame` fails here instead of silently
    /// baking a wrong "golden" value.
    func test_knownWireValues() throws {
        // 00:00:00:00 at 24 fps: every payload nibble is zero, so each byte is
        // just its piece index in the high nibble.
        let zero = try MTCWireGolden.timecode([0, 0, 0, 0], rate: .fps24)
        let zeroBytes = (0..<8).map { MTCFrame.quarterFrameByte(piece: $0, timecode: zero) }
        XCTAssertEqual(zeroBytes, [0x00, 0x10, 0x20, 0x30, 0x40, 0x50, 0x60, 0x70])
        XCTAssertEqual(MTCFrame.fullFrameBytes(zero), [0xF0, 0x7F, 0x7F, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00, 0xF7])

        // 17:30:45:12 at 25 fps. Rate bits 0b01; hours 17 = 0b10001, so piece 6
        // carries 0b0001 and piece 7 carries (0b01 << 1) | 1 = 0b011.
        let interior = try MTCWireGolden.timecode([17, 30, 45, 12], rate: .fps25)
        let bytes = (0..<8).map { MTCFrame.quarterFrameByte(piece: $0, timecode: interior) }
        XCTAssertEqual(bytes, [0x0C, 0x10, 0x2D, 0x32, 0x4E, 0x51, 0x61, 0x73])
        // Full Frame packs the rate above the hour: (0b01 << 5) | 17 = 0x31.
        XCTAssertEqual(
            MTCFrame.fullFrameBytes(interior),
            [0xF0, 0x7F, 0x7F, 0x01, 0x01, 0x31, 30, 45, 12, 0xF7]
        )
    }

    /// The clamp is contract, not an accident: an out-of-range piece index must
    /// produce the nearest valid piece's byte rather than a byte whose high
    /// nibble names a piece nobody asked for.
    func test_outOfRangePieces_clampToTheEnds() throws {
        for rate in MTCWireGolden.allRates {
            let timecode = try MTCWireGolden.timecode([23, 59, 59, rate.framesPerSecond - 1], rate: rate)
            XCTAssertEqual(
                MTCFrame.quarterFrameByte(piece: -1, timecode: timecode),
                MTCFrame.quarterFrameByte(piece: 0, timecode: timecode),
                "\(rate.rawValue)"
            )
            XCTAssertEqual(
                MTCFrame.quarterFrameByte(piece: 8, timecode: timecode),
                MTCFrame.quarterFrameByte(piece: 7, timecode: timecode),
                "\(rate.rawValue)"
            )
        }
    }

    /// Drift guard + bootstrap — see `LTCWireGoldenVectorTests` for the rationale.
    func test_committedVectors_matchCurrentSwiftOutput() throws {
        let url = try goldenURL()
        let generated = try MTCWireGolden.encoded(MTCWireGolden.make())

        guard FileManager.default.fileExists(atPath: url.path) else {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try generated.write(to: url)
            return XCTFail("golden/mtc-wire-v1.json was missing — generated it from the Swift "
                + "MTCFrame implementation. Commit the file and re-run. (To regenerate after "
                + "a deliberate change, delete the file first.)")
        }

        let committed = try JSONDecoder().decode(
            MTCWireGoldenVector.self, from: Data(contentsOf: url)
        )
        XCTAssertEqual(
            committed,
            try MTCWireGolden.make(),
            "golden/mtc-wire-v1.json drifted from the Swift MTCFrame implementation. If the "
                + "change was intentional, delete the file and re-run to regenerate, review "
                + "the diff, and update the C# OnlyCue.Core to match."
        )
    }
}
