import XCTest
@testable import OnlyCue

// The generator + drift guard for `golden/ltc-schedule-v1.json`. The contract
// model and the case matrix live in `LTCScheduleGolden.swift`.

extension LTCScheduleGolden {

    // MARK: - Case builders

    private static func streamCase(_ spec: StreamCase) throws -> LTCScheduleGoldenVector.Case {
        let stream = try stream(spec.rate, spec.sampleRate, start: streamTimecode)
        let samples = stream.samples(frameCount: spec.frameCount)
        let joins = stride(from: stream.samplesPerFrame, to: samples.count, by: stream.samplesPerFrame).map {
            LTCScheduleGoldenVector.Join(at: $0, runs: runs(of: window(of: samples, around: $0)))
        }
        return LTCScheduleGoldenVector.Case(
            label: "stream/\(spec.rate.rawValue)@\(Int(spec.sampleRate))/\(stream.startTimecode.displayString)"
                + "/x\(spec.frameCount)",
            op: "stream",
            rate: spec.rate.rawValue,
            input: LTCScheduleGoldenVector.Input(
                hours: stream.startTimecode.hours,
                minutes: stream.startTimecode.minutes,
                seconds: stream.startTimecode.seconds,
                frames: stream.startTimecode.frames,
                sampleRate: GoldenDouble(spec.sampleRate),
                amplitude: GoldenDouble(Double(amplitude)),
                frameCount: spec.frameCount
            ),
            expect: LTCScheduleGoldenVector.Expect(
                samplesPerFrame: stream.samplesPerFrame,
                totalSamples: samples.count,
                firstSampleIsHigh: samples.first.map { $0 > 0 },
                lastSampleIsHigh: samples.last.map { $0 > 0 },
                joins: joins
            )
        )
    }

    private static func streamTimecodeCase(_ rate: SMPTEFramerate, offset: Int) throws -> LTCScheduleGoldenVector.Case {
        let stream = try stream(rate, 48000, start: frameOffsetOrigin)
        return LTCScheduleGoldenVector.Case(
            label: "streamTimecode/\(rate.rawValue)/\(stream.startTimecode.displayString)/offset\(offset)",
            op: "streamTimecode",
            rate: rate.rawValue,
            input: LTCScheduleGoldenVector.Input(
                hours: stream.startTimecode.hours,
                minutes: stream.startTimecode.minutes,
                seconds: stream.startTimecode.seconds,
                frames: stream.startTimecode.frames,
                frameOffset: offset
            ),
            expect: LTCScheduleGoldenVector.Expect(
                timecode: stream.timecode(atFrameOffset: offset).displayString
            )
        )
    }

    private static func input(_ spec: ScheduleCase, timecode: Timecode) -> LTCScheduleGoldenVector.Input {
        LTCScheduleGoldenVector.Input(
            hours: timecode.hours,
            minutes: timecode.minutes,
            seconds: timecode.seconds,
            frames: timecode.frames,
            sampleRate: GoldenDouble(spec.sampleRate),
            amplitude: GoldenDouble(Double(amplitude)),
            framesPerBuffer: spec.framesPerBuffer
        )
    }

    private static func label(_ spec: ScheduleCase, timecode: Timecode) -> String {
        "\(spec.rate.rawValue)@\(Int(spec.sampleRate))/\(timecode.displayString)/fpb\(spec.framesPerBuffer)"
    }

    private static func scheduleCase(_ spec: ScheduleCase) throws -> LTCScheduleGoldenVector.Case {
        let schedule = try schedule(spec)
        return LTCScheduleGoldenVector.Case(
            label: "schedule/" + label(spec, timecode: schedule.startTimecode),
            op: "schedule",
            rate: spec.rate.rawValue,
            input: input(spec, timecode: schedule.startTimecode),
            expect: LTCScheduleGoldenVector.Expect(
                samplesPerBuffer: schedule.samplesPerBuffer,
                bufferDuration: GoldenDouble(schedule.bufferDuration)
            )
        )
    }

    private static func bufferCase(_ spec: BufferCase) throws -> LTCScheduleGoldenVector.Case {
        let schedule = try schedule(spec.schedule)
        let buffer = schedule.buffer(at: spec.index)
        var input = input(spec.schedule, timecode: schedule.startTimecode)
        input.bufferIndex = spec.index
        return LTCScheduleGoldenVector.Case(
            label: "buffer/" + label(spec.schedule, timecode: schedule.startTimecode) + "/index\(spec.index)",
            op: "buffer",
            rate: spec.schedule.rate.rawValue,
            input: input,
            expect: LTCScheduleGoldenVector.Expect(
                lastSampleIsHigh: buffer.samples.last.map { $0 > 0 },
                timecode: buffer.timecode.displayString,
                sampleCount: buffer.samples.count
            )
        )
    }

    /// The run lengths of `last(joinWindow) ++ first(joinWindow)` across the join
    /// between buffer `index` and `index + 1`. A port whose buffers do not abut
    /// cleanly produces a doubled run in the middle of this array.
    private static func bufferSeamCase(_ spec: BufferCase) throws -> LTCScheduleGoldenVector.Case {
        let schedule = try schedule(spec.schedule)
        let previous = schedule.samples(forBufferIndex: spec.index)
        let next = schedule.samples(forBufferIndex: spec.index + 1)
        let seam = previous.suffix(joinWindow) + next.prefix(joinWindow)
        var input = input(spec.schedule, timecode: schedule.startTimecode)
        input.bufferIndex = spec.index
        return LTCScheduleGoldenVector.Case(
            label: "bufferSeam/" + label(spec.schedule, timecode: schedule.startTimecode)
                + "/index\(spec.index)-\(spec.index + 1)",
            op: "bufferSeam",
            rate: spec.schedule.rate.rawValue,
            input: input,
            expect: LTCScheduleGoldenVector.Expect(
                previousEndsHigh: previous.last.map { $0 > 0 },
                nextStartsHigh: next.first.map { $0 > 0 },
                runs: runs(of: Array(seam))
            )
        )
    }

    private static func targetCountCase(_ spec: TargetCountCase) throws -> LTCScheduleGoldenVector.Case {
        let schedule = try schedule(spec.schedule)
        var input = input(spec.schedule, timecode: schedule.startTimecode)
        input.elapsedSeconds = GoldenDouble(spec.elapsedSeconds)
        input.leadBuffers = spec.leadBuffers
        return LTCScheduleGoldenVector.Case(
            label: "targetBufferCount/" + label(spec.schedule, timecode: schedule.startTimecode)
                + "/elapsed\(spec.elapsedSeconds)/lead\(spec.leadBuffers)",
            op: "targetBufferCount",
            rate: spec.schedule.rate.rawValue,
            input: input,
            expect: LTCScheduleGoldenVector.Expect(
                count: schedule.targetBufferCount(
                    elapsedSeconds: spec.elapsedSeconds,
                    leadBuffers: spec.leadBuffers
                )
            )
        )
    }

    private static func framesPerBufferCase(
        _ rate: SMPTEFramerate,
        targetSeconds: Double
    ) -> LTCScheduleGoldenVector.Case {
        LTCScheduleGoldenVector.Case(
            label: "framesPerBuffer/\(rate.rawValue)/\(targetSeconds)s",
            op: "framesPerBuffer",
            rate: rate.rawValue,
            input: LTCScheduleGoldenVector.Input(targetSeconds: GoldenDouble(targetSeconds)),
            expect: LTCScheduleGoldenVector.Expect(
                frames: LTCSchedule.framesPerBuffer(forTargetSeconds: targetSeconds, rate: rate)
            )
        )
    }

    // MARK: - Assembly

    static func make() throws -> LTCScheduleGoldenVector {
        var cases = try streamCases.map(streamCase)
        cases += try allRates.flatMap { rate in
            try frameOffsets.map { try streamTimecodeCase(rate, offset: $0) }
        }
        cases += try scheduleCases.map(scheduleCase)
        cases += try bufferCases.map(bufferCase)
        cases += try bufferSeamCases.map(bufferSeamCase)
        cases += try targetCountCases.map(targetCountCase)
        cases += allRates.flatMap { rate in
            targetSecondsValues.map { framesPerBufferCase(rate, targetSeconds: $0) }
        }
        return LTCScheduleGoldenVector(
            contract: "ltc-schedule",
            version: 1,
            note: "macOS-generated golden vectors for the OnlyCue LTC scheduling layer "
                + "(LTCFrameStream and LTCSchedule). The C# OnlyCue.Core re-implementation "
                + "must reproduce every case exactly. PCM is pinned by structure plus a "
                + "±16-sample run-length window around each join; every sample of a single "
                + "frame is already pinned by golden/ltc-wire-v1.json. To regenerate after a "
                + "deliberate change, delete golden/ltc-schedule-v1.json and re-run the suite.",
            cases: cases
        )
    }

    /// Deterministic encoding so the committed file is stable and diff-friendly.
    static func encoded(_ vector: LTCScheduleGoldenVector) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(vector)
    }
}

// MARK: - Tests

final class LTCScheduleGoldenVectorTests: XCTestCase {

    private func goldenURL() throws -> URL {
        try repoRoot().appendingPathComponent("golden", isDirectory: true)
            .appendingPathComponent("ltc-schedule-v1.json")
    }

    /// **The invariant this whole slice exists for.**
    ///
    /// `LTCSchedule` builds each buffer from a *fresh* `LTCFrameStream`, so
    /// biphase polarity is explicitly not threaded across buffer joins. Its doc
    /// comment used to call that harmless "since an LTC reader keys on
    /// transitions, not absolute polarity" — wrong reasoning, because a reset
    /// that actually flipped the level would mean a *missing* transition, which
    /// is a misread bit rather than an inversion.
    ///
    /// The real reason it is harmless: each frame emits 80 bit-boundary flips
    /// plus one mid-bit flip per `1` bit, and the parity bit forces an even
    /// number of ones — so the flip count is even and `endLevel` always equals
    /// `startLevel`. **The parity bit is what makes the buffer joins seamless.**
    /// A port with wrong parity would glitch audibly at every boundary.
    func test_endLevelAlwaysEqualsStartLevel_becauseParityMakesTheFlipCountEven() throws {
        for spec in LTCScheduleGolden.streamCases where spec.frameCount > 0 {
            let timecode = try LTCScheduleGolden.timecode(LTCScheduleGolden.streamTimecode, rate: spec.rate)
            for startLevel in [false, true] {
                let (samples, endLevel) = LTCEncoder.samples(
                    for: timecode,
                    sampleRate: spec.sampleRate,
                    amplitude: LTCScheduleGolden.amplitude,
                    startLevel: startLevel
                )
                XCTAssertEqual(endLevel, startLevel, "\(spec.rate.rawValue)@\(spec.sampleRate)")
                XCTAssertEqual(samples.last.map { $0 > 0 }, endLevel, "the last slot is emitted at the final level")
                XCTAssertEqual(LTCFrame(timecode: timecode).hasEvenParity, true, "even parity is why")
            }
        }
    }

    /// Independent pins that do **not** go through the generator, so a wrong
    /// implementation fails here rather than silently baking a wrong "golden"
    /// value. Hand-computed, not read off the implementation.
    func test_knownScheduleValues() throws {
        // `samplesPerBuffer` rounds per frame and then multiplies. 44100 / 24 is
        // 1837.5 → 1838 → ×4 = 7352. Multiplying first would give
        // round(4 × 1837.5) = 7350, i.e. two samples short per buffer forever.
        let schedule = LTCSchedule(
            startTimecode: try LTCScheduleGolden.timecode([1, 0, 0, 0], rate: .fps24),
            sampleRate: 44100,
            framesPerBuffer: 4
        )
        XCTAssertEqual(schedule.samplesPerBuffer, 7352)
        XCTAssertNotEqual(schedule.samplesPerBuffer, Int((4 * 44100.0 / 24.0).rounded()))
        XCTAssertEqual(schedule.samples(forBufferIndex: 0).count, 7352)
        XCTAssertEqual(schedule.bufferDuration, 4.0 / 24.0)

        // 0.1 s at 25 fps is 2.5 frames. Swift's half-away-from-zero rounding
        // gives 3; C#'s banker's `Math.Round` gives 2. 0.3 s is 7.5, where both
        // modes give 8 — the control.
        XCTAssertEqual(LTCSchedule.framesPerBuffer(forTargetSeconds: 0.1, rate: .fps25), 3)
        XCTAssertEqual(LTCSchedule.framesPerBuffer(forTargetSeconds: 0.5, rate: .fps25), 13)
        XCTAssertEqual(LTCSchedule.framesPerBuffer(forTargetSeconds: 0.3, rate: .fps25), 8)
        XCTAssertEqual(LTCSchedule.framesPerBuffer(forTargetSeconds: -1, rate: .fps25), 1)

        // `ceil`, not `round`: a fifth of a buffer still needs a whole buffer.
        XCTAssertEqual(schedule.targetBufferCount(elapsedSeconds: 0.2 * schedule.bufferDuration, leadBuffers: 0), 1)
        XCTAssertEqual(schedule.targetBufferCount(elapsedSeconds: -1, leadBuffers: -1), 0)
    }

    /// The tie cases have to *be* ties, or the contract goes quiet without
    /// failing. Pinned separately so a future edit to the matrix cannot silently
    /// remove the only cases that separate the two rounding modes.
    func test_theRoundingTrapCasesAreActuallyTies() {
        XCTAssertEqual(0.1 * 25.0, 2.5)
        XCTAssertEqual(0.5 * 25.0, 12.5)
        XCTAssertEqual(44100.0 / 24.0, 1837.5)
        XCTAssertTrue(LTCScheduleGolden.targetSecondsValues.contains(0.1))
        XCTAssertTrue(LTCScheduleGolden.targetSecondsValues.contains(0.5))
        XCTAssertTrue(LTCScheduleGolden.scheduleCases.contains { $0.sampleRate == 44100 && $0.rate == .fps24 })
    }

    /// Two mutants at a frame join, and the contract's honest answer to each.
    ///
    /// **Resetting the polarity at every frame is an _equivalent_ mutant.** Every
    /// frame ends at the level it started at — see
    /// `test_endLevelAlwaysEqualsStartLevel_…` — so the threaded `level` is
    /// `false` at the top of every iteration anyway, and a port that dropped the
    /// threading entirely would emit byte-identical PCM. Nothing can catch it,
    /// because there is nothing to catch. Asserted rather than assumed, so no
    /// future comment can claim the `joins` windows guard the threading.
    ///
    /// **Inverting the polarity at a join is not equivalent**, and that is what
    /// the window is sized for: it loses a transition, which is a misread bit
    /// rather than a harmless inversion. The whole second frame flips sign, so
    /// the assertion is that the difference is visible *inside* the ±`joinWindow`
    /// slice — a window too narrow to straddle the join would pass while pinning
    /// nothing.
    func test_joinWindow_catchesAnInvertedJoin_butResettingOneIsEquivalent() throws {
        /// The stream's own loop, with the level at each frame chosen by `level`.
        func concatenated(
            _ stream: LTCFrameStream,
            frameCount: Int,
            level: (_ previousEndLevel: Bool) -> Bool
        ) -> [Float] {
            var output: [Float] = []
            var next = false
            for offset in 0..<frameCount {
                let (samples, endLevel) = LTCEncoder.samples(
                    for: stream.timecode(atFrameOffset: offset),
                    sampleRate: stream.sampleRate,
                    amplitude: stream.amplitude,
                    startLevel: next
                )
                output += samples
                next = level(endLevel)
            }
            return output
        }

        for spec in LTCScheduleGolden.streamCases where spec.frameCount > 1 {
            let stream = try LTCScheduleGolden.stream(
                spec.rate, spec.sampleRate, start: LTCScheduleGolden.streamTimecode
            )
            let threaded = stream.samples(frameCount: spec.frameCount)
            let label = "\(spec.rate.rawValue)@\(Int(spec.sampleRate))/x\(spec.frameCount)"

            XCTAssertEqual(
                concatenated(stream, frameCount: spec.frameCount) { _ in false },
                threaded,
                "\(label): resetting the polarity per frame is indistinguishable from threading it"
            )

            let inverted = concatenated(stream, frameCount: spec.frameCount) { !$0 }
            XCTAssertEqual(inverted.count, threaded.count, label)
            let at = stream.samplesPerFrame
            XCTAssertNotEqual(
                LTCScheduleGolden.runs(of: LTCScheduleGolden.window(of: threaded, around: at)),
                LTCScheduleGolden.runs(of: LTCScheduleGolden.window(of: inverted, around: at)),
                "\(label): an inverted join must be visible inside the pinned window"
            )
        }
    }

    /// Run-length encoding is lossless for a `±amplitude` signal, so the window
    /// runs are equivalent to the samples they stand for.
    func test_runLengthEncoding_roundTripsTheSamples() throws {
        let stream = try LTCScheduleGolden.stream(.fps24, 48000, start: LTCScheduleGolden.streamTimecode)
        let samples = stream.samples(frameCount: 2)
        let window = LTCScheduleGolden.window(of: samples, around: stream.samplesPerFrame)
        let expanded = LTCScheduleGolden.runs(of: window).flatMap { run in
            repeatElement(Float(run[0]) * LTCScheduleGolden.amplitude, count: run[1])
        }
        XCTAssertEqual(expanded, window)
        XCTAssertEqual(window.count, 2 * LTCScheduleGolden.joinWindow)
    }

    /// Drift guard + bootstrap. When the committed file is present it must equal
    /// the current Swift output byte-for-byte (that's the contract the C# core
    /// verifies against). When it is missing — first run, or after a deliberate
    /// change where the dev deleted it to regenerate — it is written and the test
    /// fails, so the new contract is committed and reviewed rather than silently
    /// accepted in CI.
    func test_committedVectors_matchCurrentSwiftOutput() throws {
        let url = try goldenURL()
        let generated = try LTCScheduleGolden.encoded(LTCScheduleGolden.make())

        guard FileManager.default.fileExists(atPath: url.path) else {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try generated.write(to: url)
            return XCTFail("golden/ltc-schedule-v1.json was missing — generated it from the Swift "
                + "LTCFrameStream / LTCSchedule implementation. Commit the file and re-run. (To "
                + "regenerate after a deliberate change, delete the file first.)")
        }

        let committed = try JSONDecoder().decode(
            LTCScheduleGoldenVector.self, from: Data(contentsOf: url)
        )
        XCTAssertEqual(
            committed,
            try LTCScheduleGolden.make(),
            "golden/ltc-schedule-v1.json drifted from the Swift implementation. If the change "
                + "was intentional, delete the file and re-run to regenerate, review the "
                + "diff, and update the C# OnlyCue.Core to match."
        )
    }
}
