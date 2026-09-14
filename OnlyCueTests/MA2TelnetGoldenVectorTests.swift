import XCTest
@testable import OnlyCue

// The cross-platform golden-vector contract for the grandMA2 **telnet** push
// (epic #728, M1c — vector 4 of the seven in
// `docs/superpowers/specs/2026-09-14-windows-m1-contract-design.md`).
//
// macOS is the source of truth: this file emits `golden/ma2-telnet-v1.json` from
// `MA2CommandPlanner` and its three primitives, and the C# `OnlyCue.Core`
// re-implementation must reproduce every string exactly (verified on Windows CI).
//
// Unlike vectors 3 and 7, the deliverable here is *formatted text* — a wrong
// character is an `Error #` on a real console mid-show. Three hazards drive the
// case list:
//
// 1. `FadeTime.formatNumber` embeds Swift's `String(Double)` straight into the
//    command, so this is the one place `GoldenDouble` cannot help: the spelling
//    itself is the contract.
// 2. `MA2TrigTime.seconds` and `MA2CueNumber.components` both use `.rounded()`,
//    which is round-half-**away-from-zero**; .NET's `Math.Round(double)` defaults
//    to banker's and `(int)` truncates. Exact midpoints are pinned below.
// 3. `MA2Name.sanitize` filters *unicode scalars*. Iterating UTF-16 code units in
//    C# would split a non-BMP character's surrogate pair.

// MARK: - Contract model (mirrored by the C# verifier's DTO)

// MARK: - Case specifications

/// One `MA2CommandPlanner.commands` call. A struct rather than a tuple to stay
/// within SwiftLint's tuple-arity rule.
private struct PlanSpec {
    let name: String
    let cues: [MA2TelnetGoldenVector.CueInput]
    let target: MA2TelnetGoldenVector.TargetInput
    let sequenceName: String
    let startFrames: Int
    let framerate: SMPTEFramerate
}

/// One `MA2TrigTime` call.
private struct TrigTimeSpec {
    let name: String
    let time: Double
    let start: Int
    let rate: SMPTEFramerate

    init(_ name: String, _ time: Double, start: Int = 0, rate: SMPTEFramerate) {
        self.name = name
        self.time = time
        self.start = start
        self.rate = rate
    }
}

/// One `MA2Name.sanitize` call.
private struct NameSpec {
    let name: String
    let raw: String
    let slot: Int

    init(_ name: String, _ raw: String, slot: Int) {
        self.name = name
        self.raw = raw
        self.slot = slot
    }
}

// MARK: - Generator (the Swift implementation IS the contract source of truth)

enum MA2TelnetGolden {

    private static let assigned = MA2TelnetGoldenVector.TargetInput(
        sequenceSlot: 7, timecodeSlot: 3, executorPage: 1, executorNumber: 5, timecodeCommand: "goto"
    )
    private static let unassigned = MA2TelnetGoldenVector.TargetInput(
        sequenceSlot: 12, timecodeSlot: 4, executorPage: nil, executorNumber: nil, timecodeCommand: "go"
    )

    private static let planSpecs: [PlanSpec] = [
        PlanSpec(
            name: "two plain cues with an executor",
            cues: [MA2GoldenInput.cue(1, "Verse", at: 0), MA2GoldenInput.cue(2, "Chorus", at: 12.5)],
            target: assigned,
            sequenceName: "Song A",
            startFrames: 0,
            framerate: .fps25
        ),
        PlanSpec(
            name: "no executor emits no At Exec",
            cues: [MA2GoldenInput.cue(1, "Top", at: 1)],
            target: unassigned,
            sequenceName: "Song B",
            startFrames: 0,
            framerate: .fps30
        ),
        PlanSpec(
            name: "fades and notes are appended only when present",
            cues: [
                MA2GoldenInput.cue(1, "In only", at: 0, fadeIn: 2.5),
                MA2GoldenInput.cue(2, "Out only", at: 1, fadeOut: 3),
                // `0.1 + 0.2` is the classic shortest-round-trip stress value:
                // Swift and .NET must both spell it `0.30000000000000004`.
                MA2GoldenInput.cue(3, "Both", at: 2, notes: "hold", fadeIn: 0.1 + 0.2, fadeOut: 1.25)
            ],
            target: assigned,
            sequenceName: "Fades",
            startFrames: 0,
            framerate: .fps24
        ),
        PlanSpec(
            name: "quotes are stripped and note newlines collapse to one line",
            cues: [
                MA2GoldenInput.cue(
                    1, "He said \"go\"", at: 0, notes: "line one\nline \"two\"\r\nline three"
                )
            ],
            target: assigned,
            sequenceName: "Quote \"Test\"",
            startFrames: 0,
            framerate: .fps25
        ),
        PlanSpec(
            name: "commands are emitted in cue-number order, not time order",
            cues: [
                MA2GoldenInput.cue(3, "Third", at: 1),
                MA2GoldenInput.cue(1, "First", at: 9),
                MA2GoldenInput.cue(2.5, "Middle", at: 5)
            ],
            target: assigned,
            sequenceName: "Ordering",
            startFrames: 0,
            framerate: .fps30
        ),
        PlanSpec(
            name: "an unnumbered cue sorts as zero and stores as cue 0",
            cues: [MA2GoldenInput.cue(nil, "No number", at: 4), MA2GoldenInput.cue(1, "One", at: 0)],
            target: assigned,
            sequenceName: "Unnumbered",
            startFrames: 0,
            framerate: .fps25
        ),
        PlanSpec(
            name: "drop-frame with a start offset",
            cues: [MA2GoldenInput.cue(1.0025, "DF", at: 0.75)],
            target: assigned,
            sequenceName: "Drop",
            startFrames: 108_000,
            framerate: .fps30drop
        )
    ]

    private static func planCases() -> [MA2TelnetGoldenVector.PlanCase] {
        planSpecs.map { spec in
            .init(
                name: spec.name,
                cues: spec.cues,
                target: spec.target,
                sequenceName: spec.sequenceName,
                startTimecodeFrames: spec.startFrames,
                framerate: spec.framerate.rawValue,
                expect: MA2CommandPlanner.commands(
                    cues: MA2GoldenInput.cues(spec.cues),
                    target: MA2GoldenInput.target(spec.target),
                    sequenceName: spec.sequenceName,
                    startTimecodeFrames: spec.startFrames,
                    framerate: spec.framerate
                )
            )
        }
    }

    /// `0.5 × 25` and `0.75 × 30` are *exactly* 12.5 and 22.5 as doubles, so they
    /// separate `.rounded()` (13 / 23) from banker's rounding (12 / 22).
    private static let trigTimeSpecs: [TrigTimeSpec] = [
        .init("frame zero trims to a bare integer", 0, rate: .fps25),
        .init("a whole second at 25 fps", 5, rate: .fps25),
        .init("a repeating decimal keeps six places", 2.1333333, rate: .fps30),
        .init("an exact midpoint rounds away from zero at 25 fps", 0.5, rate: .fps25),
        .init("an exact midpoint rounds away from zero at 30 fps", 0.75, rate: .fps30),
        .init("a start offset shifts the absolute time", 1, start: 2_500, rate: .fps25),
        .init("drop-frame uses the nominal 30 fps base", 1.5, rate: .fps30drop),
        .init("24 fps thirds do not terminate", 1, start: 7, rate: .fps24)
    ]

    private static func trigTimeCases() -> [MA2TelnetGoldenVector.TrigTimeCase] {
        trigTimeSpecs.map { spec in
            .init(
                name: spec.name,
                cueTime: GoldenDouble(spec.time),
                startTimecodeFrames: spec.start,
                framerate: spec.rate.rawValue,
                expectSeconds: GoldenDouble(MA2TrigTime.seconds(
                    cueTime: spec.time, startTimecodeFrames: spec.start, framerate: spec.rate
                )),
                expectCommand: MA2TrigTime.command(
                    cueTime: spec.time, startTimecodeFrames: spec.start, framerate: spec.rate
                )
            )
        }
    }

    /// `0.0125 × 1000` and `1.0025 × 1000` are *exactly* 12.5 and 1002.5, so they
    /// separate `.rounded()` (13 / 1003) from banker's rounding (12 / 1002).
    private static let cueNumberSpecs: [(name: String, value: Double)] = [
        ("zero", 0),
        ("a whole number drops the sub number", 3),
        ("one decimal place", 1.15),
        ("three decimal places", 2.001),
        ("binary noise is absorbed by thousandth rounding", 1.3),
        ("an exact midpoint rounds away from zero", 0.0125),
        ("an exact midpoint above one rounds away from zero", 1.0025),
        ("a trailing zero in the sub number is trimmed", 4.12),
        ("a negative number truncates toward zero", -1.5)
    ]

    private static func cueNumberCases() -> [MA2TelnetGoldenVector.CueNumberCase] {
        cueNumberSpecs.map { spec in
            let parts = MA2CueNumber.components(from: spec.value)
            return .init(
                name: spec.name,
                value: GoldenDouble(spec.value),
                expectNumber: parts.number,
                expectSubNumber: parts.subNumber,
                expectCommandString: MA2CueNumber.commandString(from: spec.value)
            )
        }
    }

    private static let nameSpecs: [NameSpec] = [
        .init("plain ascii is unchanged", "Song One", slot: 7),
        .init("whitespace runs collapse", "Song \t  One  ", slot: 7),
        .init("embedded quotes are stripped", "He said \"go\"", slot: 7),
        .init("control characters are dropped", "Song\u{7}One", slot: 7),
        .init("non-ascii letters are dropped", "Café Set", slot: 7),
        // One non-BMP scalar. Swift filters scalars, so the whole emoji goes; a
        // UTF-16 code-unit port would split the surrogate pair.
        .init("a non-bmp scalar is dropped whole", "Set 🎵 One", slot: 7),
        .init("an all-cjk name falls back to the slot", "第一首歌", slot: 12),
        .init("an empty name falls back to the slot", "", slot: 3)
    ]

    private static func nameCases() -> [MA2TelnetGoldenVector.NameCase] {
        nameSpecs.map { spec in
            .init(
                name: spec.name,
                raw: spec.raw,
                fallbackSlot: spec.slot,
                expect: MA2Name.sanitize(spec.raw, fallbackSlot: spec.slot)
            )
        }
    }

    static func make() -> MA2TelnetGoldenVector {
        MA2TelnetGoldenVector(
            contract: "ma2-telnet",
            version: 1,
            note: "macOS-generated golden vectors for the OnlyCue grandMA2 telnet push "
                + "(MA2CommandPlanner, MA2TrigTime, MA2CueNumber, MA2Name). The C# "
                + "OnlyCue.Core re-implementation must reproduce every string byte for "
                + "byte. Doubles are round-trip-exact decimal strings; compare the parsed "
                + "IEEE-754 values, not the text — but note that the *expected* strings "
                + "embed Swift's own Double spelling, which the C# side must reproduce. "
                + "Cues are identified by index. To regenerate after a deliberate change, "
                + "delete golden/ma2-telnet-v1.json and re-run the test suite.",
            plans: planCases(),
            trigTimes: trigTimeCases(),
            cueNumbers: cueNumberCases(),
            names: nameCases()
        )
    }

    static func encoded(_ vector: MA2TelnetGoldenVector) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(vector)
    }
}

// MARK: - Tests

final class MA2TelnetGoldenVectorTests: XCTestCase {

    private func goldenURL() throws -> URL {
        try repoRoot().appendingPathComponent("golden", isDirectory: true)
            .appendingPathComponent("ma2-telnet-v1.json")
    }

    /// Independent correctness pins, hand-computed from the documented rules, so a
    /// wrong Swift implementation fails here rather than baking a wrong "golden".
    func test_knownValues() {
        // 0.5 s × 25 fps == 12.5 exactly. Away-from-zero → 13 frames → 13/25 s.
        XCTAssertEqual(MA2TrigTime.seconds(cueTime: 0.5, startTimecodeFrames: 0, framerate: .fps25), 0.52)
        XCTAssertEqual(MA2TrigTime.command(cueTime: 0.5, startTimecodeFrames: 0, framerate: .fps25), "0.52")
        // 0.75 s × 30 fps == 22.5 exactly → 23 frames → 23/30 s, six places.
        XCTAssertEqual(MA2TrigTime.command(cueTime: 0.75, startTimecodeFrames: 0, framerate: .fps30), "0.766667")
        // A whole number of frames trims the decimal point entirely.
        XCTAssertEqual(MA2TrigTime.command(cueTime: 5, startTimecodeFrames: 0, framerate: .fps25), "5")

        // 0.0125 × 1000 == 12.5 exactly → 13 thousandths; banker's would give 12.
        XCTAssertEqual(MA2CueNumber.components(from: 0.0125), .init(number: 0, subNumber: 13))
        XCTAssertEqual(MA2CueNumber.commandString(from: 0.0125), "0.013")
        XCTAssertEqual(MA2CueNumber.commandString(from: 3), "3")
        XCTAssertEqual(MA2CueNumber.commandString(from: 4.12), "4.12")

        XCTAssertEqual(MA2Name.sanitize("Song \t  One  ", fallbackSlot: 7), "Song One")
        XCTAssertEqual(MA2Name.sanitize("Set 🎵 One", fallbackSlot: 7), "Set One")
        XCTAssertEqual(MA2Name.sanitize("第一首歌", fallbackSlot: 12), "OnlyCue 12")

        // The fade spelling reaches the wire verbatim, so pin it directly.
        XCTAssertEqual(FadeTime.formatNumber(2.5), "2.5")
        XCTAssertEqual(FadeTime.formatNumber(3), "3")
        XCTAssertEqual(FadeTime.formatNumber(0.1 + 0.2), "0.30000000000000004")
    }

    /// Drift guard + bootstrap, matching the M1a/M1b generators. A missing file is
    /// written and the test fails, so a new contract is committed and reviewed
    /// rather than silently accepted in CI.
    func test_committedVectors_matchCurrentSwiftOutput() throws {
        let url = try goldenURL()
        let generated = try MA2TelnetGolden.encoded(MA2TelnetGolden.make())
        guard FileManager.default.fileExists(atPath: url.path) else {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try generated.write(to: url)
            return XCTFail("golden/ma2-telnet-v1.json was missing — generated it from the "
                + "Swift implementation. Commit the file and re-run. (To regenerate after a "
                + "deliberate change, delete the file first.)")
        }

        let committed = try JSONDecoder().decode(
            MA2TelnetGoldenVector.self, from: Data(contentsOf: url)
        )
        XCTAssertEqual(
            committed,
            MA2TelnetGolden.make(),
            "golden/ma2-telnet-v1.json drifted from the Swift implementation. If the change "
                + "was intentional, delete the file and re-run to regenerate, review the diff, "
                + "and update the C# OnlyCue.Core to match."
        )
    }
}
