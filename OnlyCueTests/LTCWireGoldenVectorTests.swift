import XCTest
@testable import OnlyCue

// The generator + drift guard for `golden/ltc-wire-v1.json`. The contract model
// and the case matrix live in `LTCWireGolden.swift`.

extension LTCWireGolden {

    private static func frameCase(_ value: [Int], rate: SMPTEFramerate) throws -> LTCWireGoldenVector.Case {
        let timecode = try timecode(value, rate: rate)
        let frame = LTCFrame(timecode: timecode)
        let parityBitIndex = LTCFrame.parityBitIndex(for: rate)
        return LTCWireGoldenVector.Case(
            label: "frame/\(rate.rawValue)/\(timecode.displayString)",
            op: "frame",
            rate: rate.rawValue,
            input: LTCWireGoldenVector.Input(
                hours: timecode.hours,
                minutes: timecode.minutes,
                seconds: timecode.seconds,
                frames: timecode.frames,
                sampleRate: nil,
                amplitude: nil,
                startLevel: nil
            ),
            expect: LTCWireGoldenVector.Expect(
                bits: String(frame.bits.map { $0 ? "1" : "0" }),
                parityBitIndex: parityBitIndex,
                parityBit: frame.bits[parityBitIndex],
                bit27: frame.bits[27],
                bit59: frame.bits[59],
                hasEvenParity: frame.hasEvenParity,
                syncWordIsValid: frame.syncWordIsValid,
                totalSamples: nil,
                endLevel: nil,
                runs: nil
            )
        )
    }

    private static func encodeCase(_ spec: EncodeCase) throws -> LTCWireGoldenVector.Case {
        let timecode = try timecode(encodeTimecode, rate: spec.rate)
        let (samples, endLevel) = LTCEncoder.samples(
            for: timecode,
            sampleRate: spec.sampleRate,
            amplitude: spec.amplitude,
            startLevel: spec.startLevel
        )
        let start = spec.startLevel ? "startHigh" : "startLow"
        return LTCWireGoldenVector.Case(
            label: "encode/\(spec.rate.rawValue)@\(Int(spec.sampleRate))/\(timecode.displayString)"
                + "/\(start)/amp\(spec.amplitudeLabel)",
            op: "encode",
            rate: spec.rate.rawValue,
            input: LTCWireGoldenVector.Input(
                hours: timecode.hours,
                minutes: timecode.minutes,
                seconds: timecode.seconds,
                frames: timecode.frames,
                sampleRate: GoldenDouble(spec.sampleRate),
                amplitude: GoldenDouble(Double(spec.amplitude)),
                startLevel: spec.startLevel
            ),
            expect: LTCWireGoldenVector.Expect(
                bits: nil,
                parityBitIndex: nil,
                parityBit: nil,
                bit27: nil,
                bit59: nil,
                hasEvenParity: nil,
                syncWordIsValid: nil,
                totalSamples: samples.count,
                endLevel: endLevel,
                runs: runs(of: samples)
            )
        )
    }

    static func make() throws -> LTCWireGoldenVector {
        let frames = try allRates.flatMap { rate in
            try frameInputs(for: rate).map { try frameCase($0, rate: rate) }
        }
        return LTCWireGoldenVector(
            contract: "ltc-wire",
            version: 1,
            note: "macOS-generated golden vectors for the OnlyCue LTC wire format (the "
                + "80-bit SMPTE 12M word and its Float PCM modulation). The C# "
                + "OnlyCue.Core re-implementation must reproduce every case exactly. "
                + "To regenerate after a deliberate LTCFrame / LTCEncoder change, "
                + "delete golden/ltc-wire-v1.json and re-run the test suite.",
            cases: frames + (try encodeCases.map(encodeCase))
        )
    }

    /// Deterministic encoding so the committed file is stable and diff-friendly.
    static func encoded(_ vector: LTCWireGoldenVector) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(vector)
    }
}

// MARK: - Tests

final class LTCWireGoldenVectorTests: XCTestCase {

    private func goldenURL() throws -> URL {
        try repoRoot().appendingPathComponent("golden", isDirectory: true)
            .appendingPathComponent("ltc-wire-v1.json")
    }

    /// Independent correctness pins that do **not** go through the generator, so
    /// a wrong `LTCFrame` / `LTCEncoder` fails here rather than silently baking a
    /// wrong "golden" value. Hand-computed from SMPTE 12M rather than read off
    /// the implementation.
    func test_knownWireValues() throws {
        // The sync word is the last 16 bits at every rate, always the same.
        let frame = LTCFrame(timecode: try LTCWireGolden.timecode([1, 2, 3, 4], rate: .fps25))
        XCTAssertEqual(String(frame.bits[64..<80].map { $0 ? "1" : "0" }), "0011111111111101")
        // 01:02:03:04 at 25 fps needs no correction, so *neither* candidate is set.
        XCTAssertFalse(frame.bits[27])
        XCTAssertFalse(frame.bits[59])

        // One frame is exactly one frame period of audio at every rate/sample-rate
        // pair in the matrix — 160 half-bit slots that tile `sampleRate / fps`.
        for spec in LTCWireGolden.encodeCases {
            let timecode = try LTCWireGolden.timecode(LTCWireGolden.encodeTimecode, rate: spec.rate)
            let (samples, _) = LTCEncoder.samples(
                for: timecode,
                sampleRate: spec.sampleRate,
                amplitude: spec.amplitude,
                startLevel: spec.startLevel
            )
            let expected = Int((spec.sampleRate / Double(spec.rate.framesPerSecond)).rounded())
            XCTAssertEqual(samples.count, expected, "\(spec.rate.rawValue)@\(spec.sampleRate)")
            XCTAssertTrue(samples.allSatisfy { abs($0) == spec.amplitude }, "\(spec.rate.rawValue): every sample is ±amplitude")
        }
    }

    /// The 24 fps / 48 kHz case is in the matrix because `halfBitSamples` is
    /// exactly 12.5 there, so every odd slot boundary is a midpoint tie. Pinned
    /// independently: this is the one number that separates Swift's
    /// half-away-from-zero rounding from C#'s banker's rounding, and if the case
    /// ever stopped being a tie the contract would go quiet without failing.
    func test_theRoundingTrapCaseIsActuallyATie() {
        let halfBitSamples = 48000.0 / (160.0 * 24.0)
        XCTAssertEqual(halfBitSamples, 12.5)
        XCTAssertTrue(LTCWireGolden.encodeCases.contains { $0.rate == .fps24 && $0.sampleRate == 48000 })
        // Half-away-from-zero: slot 1 ends at 12.5 → 13, not the 12 banker's
        // rounding would give. The first two runs therefore differ in length.
        XCTAssertEqual(Int((1.0 * halfBitSamples).rounded()), 13)
        XCTAssertEqual(Int((3.0 * halfBitSamples).rounded()), 38)
    }

    /// Run-length encoding is lossless for a `±amplitude` signal: the runs
    /// expand back to the samples. Without this the vector could be pinning a
    /// buggy encoder faithfully.
    func test_runLengthEncoding_roundTripsTheSamples() throws {
        let timecode = try LTCWireGolden.timecode([1, 2, 3, 4], rate: .fps24)
        let (samples, _) = LTCEncoder.samples(for: timecode, sampleRate: 48000, amplitude: 0.8)
        let expanded = LTCWireGolden.runs(of: samples).flatMap { run in
            repeatElement(Float(run[0]) * 0.8, count: run[1])
        }
        XCTAssertEqual(expanded, samples)
    }

    /// Drift guard + bootstrap. When the committed file is present it must equal
    /// the current Swift output byte-for-byte (that's the contract the C# core
    /// verifies against). When it is missing — first run, or after a deliberate
    /// change where the dev deleted it to regenerate — it is written and the test
    /// fails, so the new contract is committed and reviewed rather than silently
    /// accepted in CI.
    func test_committedVectors_matchCurrentSwiftOutput() throws {
        let url = try goldenURL()
        let generated = try LTCWireGolden.encoded(LTCWireGolden.make())

        guard FileManager.default.fileExists(atPath: url.path) else {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try generated.write(to: url)
            return XCTFail("golden/ltc-wire-v1.json was missing — generated it from the Swift "
                + "LTCFrame / LTCEncoder implementation. Commit the file and re-run. (To "
                + "regenerate after a deliberate change, delete the file first.)")
        }

        let committed = try JSONDecoder().decode(
            LTCWireGoldenVector.self, from: Data(contentsOf: url)
        )
        XCTAssertEqual(
            committed,
            try LTCWireGolden.make(),
            "golden/ltc-wire-v1.json drifted from the Swift implementation. If the change "
                + "was intentional, delete the file and re-run to regenerate, review the "
                + "diff, and update the C# OnlyCue.Core to match."
        )
    }
}
