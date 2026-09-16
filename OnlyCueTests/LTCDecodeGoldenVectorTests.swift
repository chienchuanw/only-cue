import XCTest
@testable import OnlyCue

// The generator + drift guard for `golden/ltc-decode-v1.json`. The contract
// model, the signal matrix and the recipe builder live in `LTCDecodeGolden.swift`.

extension LTCDecodeGolden {

    // MARK: - Case builders

    private static func input(_ signal: Signal) -> LTCDecodeGoldenVector.Input {
        LTCDecodeGoldenVector.Input(
            rate: signal.rate.rawValue,
            sampleRate: GoldenDouble(signal.sampleRate),
            amplitude: GoldenDouble(Double(signal.amplitude)),
            timecode: signal.start,
            frameCount: signal.frameCount,
            leadSilenceSamples: signal.leadSilenceSamples,
            trailSilenceSamples: signal.trailSilenceSamples,
            truncateToSamples: signal.truncateToSamples,
            flipBitInFrame: signal.flipBitInFrame,
            flipBitIndices: signal.flipBitIndices,
            offsetBy: GoldenDouble(signal.offsetBy.map { Double($0) })
        )
    }

    private static func label(_ op: String, _ signal: Signal, start: Timecode) -> String {
        "\(op)/\(signal.label)/\(signal.rate.rawValue)@\(Int(signal.sampleRate))"
            + "/\(start.displayString)/x\(signal.frameCount)"
    }

    private static func expect(
        _ op: String,
        signal: Signal,
        samples: [Float],
        pipeline: Pipeline
    ) -> LTCDecodeGoldenVector.Expect {
        var expect = LTCDecodeGoldenVector.Expect(sampleCount: samples.count)
        switch op {
        case "transitions":
            expect.transitionCount = pipeline.transitions.count
            expect.firstTransitions = Array(pipeline.transitions.prefix(edgeTransitions))
            expect.lastTransitions = Array(pipeline.transitions.suffix(edgeTransitions))
        case "halfBit":
            expect.halfBitSamples = GoldenDouble(pipeline.halfBitSamples)
        case "framesPerSecond":
            expect.framesPerSecond = pipeline.framesPerSecond
        case "bits":
            let bits = pipeline.bits ?? []
            expect.bitCount = bits.count
            expect.firstBits = bitString(Array(bits.prefix(edgeBits)))
            expect.lastBits = bitString(Array(bits.suffix(edgeBits)))
        default:
            expect.frames = LTCDecoder.decode(samples: samples, sampleRate: signal.sampleRate).map {
                LTCDecodeGoldenVector.Frame(timecode: $0.timecode.displayString, startSample: $0.startSample)
            }
        }
        return expect
    }

    private static func cases(for signal: Signal) throws -> [LTCDecodeGoldenVector.Case] {
        let start = try timecode(signal.start, rate: signal.rate)
        let samples = try samples(for: signal)
        let pipeline = pipeline(of: samples, sampleRate: signal.sampleRate)
        return ops.map { op in
            LTCDecodeGoldenVector.Case(
                label: label(op, signal, start: start),
                op: op,
                input: input(signal),
                expect: expect(op, signal: signal, samples: samples, pipeline: pipeline)
            )
        }
    }

    // MARK: - Assembly

    static func make() throws -> LTCDecodeGoldenVector {
        LTCDecodeGoldenVector(
            contract: "ltc-decode",
            version: 1,
            note: "macOS-generated golden vectors for the OnlyCue LTC decoder. The C# OnlyCue.Core "
                + "re-implementation must reproduce every case exactly. Signals are recipes, not "
                + "sample dumps: both sides build the same [Float] from the input fields, applying "
                + "the mutations in the order documented on LTCDecodeGolden.samples(for:), and "
                + "expect.sampleCount fingerprints the result. The five ops tap the pipeline stage "
                + "by stage so a failure localises. To regenerate after a deliberate change, delete "
                + "golden/ltc-decode-v1.json and re-run the suite.",
            cases: try allSignals.flatMap(cases(for:))
        )
    }

    /// Deterministic encoding so the committed file is stable and diff-friendly.
    static func encoded(_ vector: LTCDecodeGoldenVector) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(vector)
    }
}

// MARK: - Tests

final class LTCDecodeGoldenVectorTests: XCTestCase {

    private func goldenURL() throws -> URL {
        try repoRoot().appendingPathComponent("golden", isDirectory: true)
            .appendingPathComponent("ltc-decode-v1.json")
    }

    private func clean(_ rate: SMPTEFramerate, _ sampleRate: Double) throws -> LTCDecodeGolden.Signal {
        let signal = LTCDecodeGolden.cleanSignals.first {
            $0.label == "clean" && $0.rate == rate && $0.sampleRate == sampleRate
        }
        return try XCTUnwrap(signal)
    }

    private func structural(_ label: String) throws -> LTCDecodeGolden.Signal {
        try XCTUnwrap(LTCDecodeGolden.structuralSignals.first { $0.label == label })
    }

    private func decode(_ signal: LTCDecodeGolden.Signal) throws -> [LTCDecoder.DecodedFrame] {
        LTCDecoder.decode(samples: try LTCDecodeGolden.samples(for: signal), sampleRate: signal.sampleRate)
    }

    /// The control run minus the one frame `signal`'s mutation lands on, matched
    /// **by timecode**. The decoder drops the leading and trailing frame of every
    /// run, so an index into the encoded run is not an index into the decoded one;
    /// and the guard below is what keeps this from degenerating into "the control
    /// never decoded that frame either, so of course nothing changed".
    private func withoutTheCorruptedFrame(
        _ control: [LTCDecoder.DecodedFrame],
        of signal: LTCDecodeGolden.Signal
    ) throws -> [LTCDecoder.DecodedFrame] {
        let start = try LTCDecodeGolden.timecode(signal.start, rate: signal.rate)
        let offset = try XCTUnwrap(signal.flipBitInFrame)
        let corrupted = Timecode(frameCount: start.frameCount + offset, rate: signal.rate)
        XCTAssertTrue(
            control.contains { $0.timecode == corrupted },
            "the control must decode \(corrupted.displayString) or the case proves nothing"
        )
        return control.filter { $0.timecode != corrupted }
    }

    /// **Hazard 3, stated as a rule rather than as a golden number.**
    ///
    /// The comparator starts at `state == 0` and the first latch sets the state
    /// *without* recording an index — so a signal that opens high has no
    /// transition at sample 0, and every `startSample` in the contract is
    /// measured from the first real sign change. A port that records the first
    /// latch shifts every index by one position and every `startSample` to 0.
    func test_theFirstLatchIsNotATransition() {
        XCTAssertEqual(LTCDecoder.transitionIndices(in: [0.8, -0.8, 0.8, -0.8]), [1, 2, 3])
        XCTAssertEqual(LTCDecoder.transitionIndices(in: [-0.8, 0.8, -0.8]), [1, 2])
    }

    /// **Hazard 5, hand-derived.**
    ///
    /// At 24 fps / 48 kHz a half-bit slot is exactly 12.5 samples, so the slot
    /// boundaries `round(k × 12.5)` alternate 13 and 12 samples long. Biphase
    /// mark puts a transition at every bit boundary and one more in the middle of
    /// every `1`, so the only inter-transition intervals that can occur are
    ///
    /// - **13 then 12** — the two halves of a `1`, and
    /// - **25** — a whole `0` bit.
    ///
    /// `estimateHalfBitSamples` takes the minimum (12), keeps everything strictly
    /// below `1.5 × 12 = 18`, and averages. So the cluster is exactly the 12s and
    /// the 13s, the 25s are excluded, and the mean lands on 12.5 up to the single
    /// unpaired 13 at the end of the buffer. That is the whole of hazard 5:
    /// `<=` instead of `<`, or a median, or an integer mean, moves it.
    func test_halfBitCluster_isExactlyTheTwelveAndThirteenSampleIntervals() throws {
        let signal = try clean(.fps24, 48000)
        let samples = try LTCDecodeGolden.samples(for: signal)
        let transitions = LTCDecoder.transitionIndices(in: samples)
        let intervals = zip(transitions.dropFirst(), transitions).map { $0 - $1 }

        XCTAssertEqual(Set(intervals), [12, 13, 25], "24 fps @ 48 kHz can only produce these three intervals")
        let cluster = intervals.filter { $0 < 18 }
        XCTAssertEqual(Set(cluster), [12, 13])
        XCTAssertEqual(cluster.count, intervals.count - intervals.filter { $0 == 25 }.count)

        let halfBit = try XCTUnwrap(LTCDecoder.estimateHalfBitSamples(transitions: transitions))
        XCTAssertEqual(halfBit, Double(cluster.reduce(0, +)) / Double(cluster.count))
        XCTAssertEqual(halfBit, 12.5, accuracy: 0.01, "one unpaired 13 at the buffer's end is the whole error")
        XCTAssertEqual(LTCDecoder.framesPerSecond(sampleRate: 48000, halfBitSamples: halfBit), 24)
    }

    /// **Hazard 8, the reason this slice exists.**
    ///
    /// `extractFrames` advances 80 bits on a **sync match**, not on a **valid
    /// frame**. So a frame whose parity has been broken is *consumed* and the
    /// search resumes cleanly after it. The assertion that catches a port which
    /// puts the advance inside the validity check is therefore not "one frame is
    /// missing" — it is that *only* that frame is missing and every other frame
    /// comes back at a byte-identical `startSample`.
    ///
    /// The control is the same recipe with no mutation, so the two runs differ in
    /// exactly one bit on the wire. The corrupted frame is found by timecode
    /// rather than by index, because the decoder drops the leading and trailing
    /// frame of every run — an index into the *encoded* run is not an index into
    /// the *decoded* one.
    func test_aParityBrokenFrameIsConsumed_soTheFramesAfterItKeepTheirOffsets() throws {
        let corrupted = try structural("parity-flipped-middle-frame")
        let control = try decode(try clean(.fps24, 48000))

        XCTAssertGreaterThanOrEqual(control.count, 3, "the corrupted frame needs neighbours on both sides")
        XCTAssertEqual(try decode(corrupted), try withoutTheCorruptedFrame(control, of: corrupted))
    }

    /// **A well-formed word can still name no timecode.** `bcd-out-of-range`
    /// drives the frames field out of range and flips the parity position back, so
    /// the word passes `isWellFormed` and is refused only by
    /// `timecode(framesPerSecond:)`. Validity and range are two gates; a port that
    /// folds them into one passes every clean case and fails here.
    ///
    /// The word is rebuilt from the frame the mutation actually lands on
    /// (`flipBitInFrame`), not from the run's first frame — otherwise this would
    /// pin arithmetic that never reaches the wire.
    func test_bcdOutOfRange_isWellFormedButNamesNoTimecode() throws {
        let signal = try structural("bcd-out-of-range")
        let start = try LTCDecodeGolden.timecode(signal.start, rate: signal.rate)
        let offset = try XCTUnwrap(signal.flipBitInFrame)
        var bits = LTCFrame(timecode: Timecode(frameCount: start.frameCount + offset, rate: signal.rate)).bits
        for index in try XCTUnwrap(signal.flipBitIndices) { bits[index].toggle() }
        let frame = LTCFrame(bits: bits)

        XCTAssertTrue(frame.isWellFormed, "an even number of flips preserves parity")
        XCTAssertEqual(frame.frames, 33, "no rate in the matrix has a frame 33")
        XCTAssertNil(frame.timecode(framesPerSecond: 24))

        // Refused at the range gate, not the validity gate — so, exactly as with a
        // broken parity, only that frame goes missing.
        let control = try decode(try clean(.fps24, 48000))
        XCTAssertEqual(try decode(signal), try withoutTheCorruptedFrame(control, of: signal))
    }

    /// **The DC ladder straddles a root, and the root is algebra, not a golden
    /// number.** For a `±A` square wave with offset `D` the latch stops firing
    /// once `A − D < 0.3·√(D² + A²)`; at `A = 0.8` that root is ≈ 0.51462. The
    /// contract pins one rung either side, which is what stops a port from adding
    /// a DC blocker: with one, 0.55 would decode.
    func test_theDCLadderStraddlesTheLatchRoot() throws {
        let amplitude = Double(LTCEncoder.defaultAmplitude)
        func latches(_ offset: Double) -> Bool {
            amplitude - offset >= 0.3 * (offset * offset + amplitude * amplitude).squareRoot()
        }
        XCTAssertTrue(latches(0.5))
        XCTAssertFalse(latches(0.55))

        for offset in LTCDecodeGolden.dcOffsets {
            let signal = try structural("dc-offset/d\(offset)")
            XCTAssertEqual(try decode(signal).isEmpty, !latches(Double(offset)), "offset \(offset)")
        }
    }

    /// **The silence floor's position, not merely its existence.** The signal is
    /// a square wave at `±amplitude`, so its RMS is the amplitude; the ladder
    /// puts two rungs above `silenceRMSFloor` (1e-4) and one below, with the
    /// middle rung sitting exactly *on* it — which is what pins `>=` rather than
    /// `>`.
    func test_theSilenceFloorLadderStraddlesTheFloor() throws {
        XCTAssertEqual(LTCDecoder.silenceRMSFloor, 1e-4)
        for amplitude in LTCDecodeGolden.silenceFloorAmplitudes {
            let signal = try structural("silence-floor/a\(amplitude)")
            let samples = try LTCDecodeGolden.samples(for: signal)
            let transitions = LTCDecoder.transitionIndices(in: samples)
            XCTAssertEqual(
                transitions.isEmpty,
                amplitude < LTCDecoder.silenceRMSFloor,
                "amplitude \(amplitude) against a floor of \(LTCDecoder.silenceRMSFloor)"
            )
        }
    }

    /// The recipe builder has to reproduce the production stream exactly when no
    /// mutation is asked for, or every clean case pins the builder rather than
    /// the decoder.
    func test_anUnmutatedRecipe_isTheProductionFrameStream() throws {
        for signal in LTCDecodeGolden.cleanSignals {
            let stream = LTCFrameStream(
                startTimecode: try LTCDecodeGolden.timecode(signal.start, rate: signal.rate),
                sampleRate: signal.sampleRate,
                amplitude: signal.amplitude
            )
            XCTAssertEqual(
                try LTCDecodeGolden.samples(for: signal),
                stream.samples(frameCount: signal.frameCount),
                signal.label
            )
        }
    }

    /// Drift guard + bootstrap. When the committed file is present it must equal
    /// the current Swift output byte-for-byte (that's the contract the C# core
    /// verifies against). When it is missing — first run, or after a deliberate
    /// change where the dev deleted it to regenerate — it is written and the test
    /// fails, so the new contract is committed and reviewed rather than silently
    /// accepted in CI.
    func test_committedVectors_matchCurrentSwiftOutput() throws {
        let url = try goldenURL()
        let generated = try LTCDecodeGolden.encoded(LTCDecodeGolden.make())

        guard FileManager.default.fileExists(atPath: url.path) else {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try generated.write(to: url)
            return XCTFail("golden/ltc-decode-v1.json was missing — generated it from the Swift "
                + "LTCDecoder implementation. Commit the file and re-run. (To regenerate after a "
                + "deliberate change, delete the file first.)")
        }

        let committed = try JSONDecoder().decode(
            LTCDecodeGoldenVector.self, from: Data(contentsOf: url)
        )
        XCTAssertEqual(
            committed,
            try LTCDecodeGolden.make(),
            "golden/ltc-decode-v1.json drifted from the Swift implementation. If the change "
                + "was intentional, delete the file and re-run to regenerate, review the "
                + "diff, and update the C# OnlyCue.Core to match."
        )
    }
}
