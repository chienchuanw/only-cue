import XCTest
@testable import OnlyCue

// The generator + drift guard for `golden/mtc-schedule-v1.json`. The contract
// model and the case matrix live in `MTCScheduleGolden.swift`.

extension MTCScheduleGolden {

    // MARK: - Case builders

    private static func baseInput(_ schedule: MTCSchedule) -> MTCScheduleGoldenVector.Input {
        MTCScheduleGoldenVector.Input(
            hours: schedule.startTimecode.hours,
            minutes: schedule.startTimecode.minutes,
            seconds: schedule.startTimecode.seconds,
            frames: schedule.startTimecode.frames,
            anchorHostTime: schedule.anchorHostTime,
            ticksPerSecond: GoldenDouble(schedule.ticksPerSecond)
        )
    }

    private static func cadenceCase(
        _ rate: SMPTEFramerate,
        ticksPerSecond: Double
    ) throws -> MTCScheduleGoldenVector.Case {
        let schedule = try schedule(rate, ticksPerSecond)
        return MTCScheduleGoldenVector.Case(
            label: "cadence/\(rate.rawValue)/\(label(ticksPerSecond))",
            op: "cadence",
            rate: rate.rawValue,
            input: baseInput(schedule),
            expect: MTCScheduleGoldenVector.Expect(
                ticksPerQuarterFrame: GoldenDouble(schedule.ticksPerQuarterFrame)
            )
        )
    }

    private static func sequenceCase(_ rate: SMPTEFramerate, index: Int) throws -> MTCScheduleGoldenVector.Case {
        let schedule = try schedule(rate, 1_000_000_000)
        var input = baseInput(schedule)
        input.sequenceIndex = index
        return MTCScheduleGoldenVector.Case(
            label: "sequenceTimecode/\(rate.rawValue)/\(schedule.startTimecode.displayString)/seq\(index)",
            op: "sequenceTimecode",
            rate: rate.rawValue,
            input: input,
            expect: MTCScheduleGoldenVector.Expect(
                timecode: schedule.timecode(forSequence: index).displayString
            )
        )
    }

    private static func quarterFrameCase(
        _ rate: SMPTEFramerate,
        ticksPerSecond: Double,
        index: Int
    ) throws -> MTCScheduleGoldenVector.Case {
        let schedule = try schedule(rate, ticksPerSecond)
        var input = baseInput(schedule)
        input.quarterFrameIndex = index
        return MTCScheduleGoldenVector.Case(
            label: "quarterFrame/\(rate.rawValue)/\(label(ticksPerSecond))/index\(index)",
            op: "quarterFrame",
            rate: rate.rawValue,
            input: input,
            expect: MTCScheduleGoldenVector.Expect(
                byte: Int(schedule.byte(forQuarterFrame: index)),
                timestamp: schedule.timestamp(forQuarterFrame: index)
            )
        )
    }

    private static func windowCase(_ spec: WindowCase) throws -> MTCScheduleGoldenVector.Case {
        let schedule = try schedule(.fps24, 1_000_000_000)
        let from = tick(schedule, spec.from)
        let until = tick(schedule, spec.until)
        var input = baseInput(schedule)
        input.from = from
        input.until = until
        return MTCScheduleGoldenVector.Case(
            label: "batch/24/1e9/\(spec.label)",
            op: "batch",
            rate: SMPTEFramerate.fps24.rawValue,
            input: input,
            expect: MTCScheduleGoldenVector.Expect(
                messages: encode(schedule.batch(from: from, until: until))
            )
        )
    }

    private static func chainCase(_ spec: ChainCase) throws -> MTCScheduleGoldenVector.Case {
        let schedule = try schedule(spec.rate, spec.ticksPerSecond)
        let boundaries = spec.boundaries.map { tick(schedule, $0) }
        let label = "batchChain/\(spec.rate.rawValue)/\(label(spec.ticksPerSecond))/\(spec.note)"
        guard zip(boundaries, boundaries.dropFirst()).allSatisfy({ $0 < $1 }) else {
            throw MTCScheduleGoldenError.boundariesNotIncreasing(label: label)
        }
        var input = baseInput(schedule)
        input.boundaries = boundaries
        let windows = zip(boundaries, boundaries.dropFirst()).map {
            encode(schedule.batch(from: $0, until: $1))
        }
        return MTCScheduleGoldenVector.Case(
            label: label,
            op: "batchChain",
            rate: spec.rate.rawValue,
            input: input,
            expect: MTCScheduleGoldenVector.Expect(
                windows: windows,
                combined: encode(schedule.batch(from: boundaries[0], until: boundaries[boundaries.count - 1]))
            )
        )
    }

    // MARK: - Assembly

    static func make() throws -> MTCScheduleGoldenVector {
        var cases = try allRates.flatMap { rate in
            try clocks.map { try cadenceCase(rate, ticksPerSecond: $0) }
        }
        cases += try allRates.flatMap { rate in
            try sequenceIndices.map { try sequenceCase(rate, index: $0) }
        }
        cases += try messageClocks.flatMap { clock in
            try quarterFrameIndices.map {
                try quarterFrameCase(clock.rate, ticksPerSecond: clock.ticksPerSecond, index: $0)
            }
        }
        cases += try windowCases.map(windowCase)
        cases += try chainCases.map(chainCase)
        return MTCScheduleGoldenVector(
            contract: "mtc-schedule",
            version: 1,
            note: "macOS-generated golden vectors for the OnlyCue MTC scheduling layer "
                + "(MTCSchedule). The C# OnlyCue.Core re-implementation must reproduce every "
                + "case exactly. batchChain is the load-bearing op: concat(windows) must equal "
                + "combined, so a message dropped at a tiled seam and one duplicated there fail "
                + "differently. hostTicksPerSecond() is out of contract — it is Mach-specific. "
                + "To regenerate after a deliberate change, delete golden/mtc-schedule-v1.json "
                + "and re-run the suite.",
            cases: cases
        )
    }

    /// Deterministic encoding so the committed file is stable and diff-friendly.
    static func encoded(_ vector: MTCScheduleGoldenVector) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(vector)
    }
}

// MARK: - Tests

final class MTCScheduleGoldenVectorTests: XCTestCase {

    private func goldenURL() throws -> URL {
        try repoRoot().appendingPathComponent("golden", isDirectory: true)
            .appendingPathComponent("mtc-schedule-v1.json")
    }

    /// Independent pins that do **not** go through the generator. Hand-computed
    /// from the cadence rather than read off the implementation.
    func test_knownScheduleValues() throws {
        let schedule = try MTCScheduleGolden.schedule(.fps25, 1_000_000_000)
        // 25 fps × 4 = 100 messages per second at nanosecond ticks.
        XCTAssertEqual(schedule.ticksPerQuarterFrame, 10_000_000)
        XCTAssertEqual(schedule.timestamp(forQuarterFrame: 0), MTCScheduleGolden.anchor)
        XCTAssertEqual(schedule.timestamp(forQuarterFrame: 8), MTCScheduleGolden.anchor + 80_000_000)
        // Negative indices clamp rather than running backwards past the anchor.
        XCTAssertEqual(schedule.timestamp(forQuarterFrame: -5), MTCScheduleGolden.anchor)
        XCTAssertEqual(schedule.byte(forQuarterFrame: -5), schedule.byte(forQuarterFrame: 0))
        // Eight messages carry one value and advance it by two frames.
        XCTAssertEqual(schedule.timecode(forSequence: 0), schedule.startTimecode)
        XCTAssertEqual(
            schedule.timecode(forSequence: 1).frameCount,
            schedule.startTimecode.frameCount + 2
        )
    }

    /// The quantise in `quarterFrameIndex(atOrAfter:)` is load-bearing, not
    /// padding. Reproduces what a port without it would do and counts the
    /// damage, so the number in the contract's header comment is an assertion
    /// rather than a claim: at nanosecond ticks a tiled chain would drop more
    /// than a third of all messages at 24 fps, and none at 25 fps, where the
    /// quarter-frame period is a whole number of ticks.
    func test_theQuantiseIsLoadBearing_atNanosecondTicks() throws {
        func dropped(rate: SMPTEFramerate) throws -> Int {
            let schedule = try MTCScheduleGolden.schedule(rate, 1_000_000_000)
            let period = schedule.ticksPerQuarterFrame
            return (0..<200).filter { index in
                let offset = Double(schedule.timestamp(forQuarterFrame: index)) - Double(MTCScheduleGolden.anchor)
                guard offset > 0 else { return false }
                // No quantise: `ceil` of a value a hair above the integer index
                // lands on the *next* index, so this message never gets emitted.
                return Int((offset / period).rounded(.up)) != index
            }.count
        }
        XCTAssertEqual(try dropped(rate: .fps24), 74)
        XCTAssertEqual(try dropped(rate: .fps30), 66)
        XCTAssertEqual(try dropped(rate: .fps25), 0, "the period is exactly 10 000 000 ticks here")
    }

    /// Tiling is the property the windowing exists to provide: passing the
    /// previous call's `until` as the next call's `from` must yield every
    /// message exactly once. Asserted over the committed chains directly, so a
    /// chain whose vector was regenerated from a broken implementation still
    /// fails here.
    func test_tiledWindows_yieldEveryMessageExactlyOnce() throws {
        for spec in MTCScheduleGolden.chainCases {
            let schedule = try MTCScheduleGolden.schedule(spec.rate, spec.ticksPerSecond)
            let boundaries = spec.boundaries.map { MTCScheduleGolden.tick(schedule, $0) }
            let windows = zip(boundaries, boundaries.dropFirst()).map {
                schedule.batch(from: $0, until: $1)
            }
            let combined = schedule.batch(from: boundaries[0], until: boundaries[boundaries.count - 1])
            let label = "\(spec.rate.rawValue)/\(MTCScheduleGolden.label(spec.ticksPerSecond))/\(spec.note)"
            XCTAssertEqual(windows.flatMap { $0 }, combined, label)
            XCTAssertFalse(combined.isEmpty, "\(label): a chain that yields nothing pins nothing")
            XCTAssertEqual(
                Set(combined.map(\.timestamp)).count,
                combined.count,
                "\(label): no message may appear twice"
            )
        }
    }

    /// The coarse clock has to *be* coarse enough to make every odd index a
    /// rounding tie, or the only case separating half-away-from-zero from
    /// banker's rounding inside `timestamp(forQuarterFrame:)` goes quiet without
    /// failing.
    func test_theCoarseClockCaseIsActuallyATie() throws {
        let schedule = try MTCScheduleGolden.schedule(.fps25, 50)
        XCTAssertEqual(schedule.ticksPerQuarterFrame, 0.5)
        // Half away from zero: index 1 is at 0.5 ticks → 1, not the 0 banker's
        // rounding would give.
        XCTAssertEqual(schedule.timestamp(forQuarterFrame: 1), MTCScheduleGolden.anchor + 1)
        XCTAssertEqual(schedule.timestamp(forQuarterFrame: 5), MTCScheduleGolden.anchor + 3)
        XCTAssertTrue(MTCScheduleGolden.messageClocks.contains { $0.ticksPerSecond == 50 })
    }

    /// Drift guard + bootstrap. When the committed file is present it must equal
    /// the current Swift output byte-for-byte (that's the contract the C# core
    /// verifies against). When it is missing — first run, or after a deliberate
    /// change where the dev deleted it to regenerate — it is written and the test
    /// fails, so the new contract is committed and reviewed rather than silently
    /// accepted in CI.
    func test_committedVectors_matchCurrentSwiftOutput() throws {
        let url = try goldenURL()
        let generated = try MTCScheduleGolden.encoded(MTCScheduleGolden.make())

        guard FileManager.default.fileExists(atPath: url.path) else {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try generated.write(to: url)
            return XCTFail("golden/mtc-schedule-v1.json was missing — generated it from the Swift "
                + "MTCSchedule implementation. Commit the file and re-run. (To regenerate after a "
                + "deliberate change, delete the file first.)")
        }

        let committed = try JSONDecoder().decode(
            MTCScheduleGoldenVector.self, from: Data(contentsOf: url)
        )
        XCTAssertEqual(
            committed,
            try MTCScheduleGolden.make(),
            "golden/mtc-schedule-v1.json drifted from the Swift implementation. If the change "
                + "was intentional, delete the file and re-run to regenerate, review the "
                + "diff, and update the C# OnlyCue.Core to match."
        )
    }
}
