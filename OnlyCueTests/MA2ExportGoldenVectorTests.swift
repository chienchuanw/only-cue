import XCTest
@testable import OnlyCue

// The cross-platform golden-vector contract for the four grandMA2 **export
// artifacts** (epic #728, M1c — vector 5 of the seven in
// `docs/superpowers/specs/2026-09-14-windows-m1-contract-design.md`).
//
// macOS is the source of truth: this file emits `golden/ma2-export-v1.json` from
// `MA2PushPlanner` (sequence XML + timecode XML + the FTP command list) and
// `MA2PluginGenerator.bundle` (the Lua plugin + its manifest XML), and the C#
// `OnlyCue.Core` re-implementation must reproduce all four byte for byte.
//
// Every artifact is transported as an **array of lines** rather than one escaped
// blob: `components(separatedBy: "\n")` round-trips losslessly (a `\r\n` survives
// as a trailing `\r`) and keeps the committed vector diff-reviewable, which the
// spec's encoding rules ask for.
//
// The hazards this pins, beyond vector 4's rounding and Double-spelling:
//
// - `MA2SequenceXMLGenerator.escape` handles exactly `&`, `<`, `>` and `"` and
//   deliberately leaves `'` alone. `XmlWriter` escapes a different set.
// - The timecode generator emits events in **time** order carrying the
//   **number**-ordered sequence index, so the two orders must disagree in a case.
// - `MA2PluginGenerator` escapes commands for a Lua single-quoted literal and
//   wraps XML in a long bracket whose `=` level is raised on collision.

// MARK: - Contract model (mirrored by the C# verifier's DTO)

struct MA2ExportGoldenVector: Codable, Equatable {
    let contract: String   // "ma2-export"
    let version: Int       // 1
    let note: String
    let cases: [ExportCase]

    /// Reuses vector 4's cue and target shapes so the two contracts cannot drift
    /// apart in how they describe the same inputs.
    struct ExportCase: Codable, Equatable {
        let name: String
        let cues: [MA2TelnetGoldenVector.CueInput]
        let target: MA2TelnetGoldenVector.TargetInput
        let sequenceName: String
        let timecodeName: String
        let pluginName: String
        let startTimecodeFrames: Int
        let lengthFrames: Int
        let framerate: String
        let showfile: String
        /// A fixed literal, never `Date()` — the spec forbids a live clock in any
        /// generator.
        let datetime: String
        let expect: Artifacts
    }

    struct Artifacts: Codable, Equatable {
        let sequenceFilename: String
        let sequenceXML: [String]
        let timecodeFilename: String
        let timecodeXML: [String]
        let commands: [String]
        let luaFilename: String
        let lua: [String]
        let manifestFilename: String
        let manifestXML: [String]
    }
}

// MARK: - Case specifications

private struct ExportSpec {
    let name: String
    let cues: [MA2TelnetGoldenVector.CueInput]
    let target: MA2TelnetGoldenVector.TargetInput
    let sequenceName: String
    let timecodeName: String
    let pluginName: String
    let startFrames: Int
    let lengthFrames: Int
    let framerate: SMPTEFramerate
}

// MARK: - Generator (the Swift implementation IS the contract source of truth)

enum MA2ExportGolden {

    /// Every case shares these so a diff between cases is only ever about the
    /// cues and the target.
    private static let showfile = "OnlyCueShow"
    private static let datetime = "2026-01-02T03:04:05"

    private static let assigned = MA2TelnetGoldenVector.TargetInput(
        sequenceSlot: 7, timecodeSlot: 3, executorPage: 1, executorNumber: 5, timecodeCommand: "goto"
    )
    private static let unassigned = MA2TelnetGoldenVector.TargetInput(
        sequenceSlot: 12, timecodeSlot: 4, executorPage: nil, executorNumber: nil, timecodeCommand: "go"
    )

    private static let specs: [ExportSpec] = [
        ExportSpec(
            name: "two cues with an executor",
            cues: [MA2GoldenInput.cue(1, "Verse", at: 0), MA2GoldenInput.cue(2, "Chorus", at: 12.5)],
            target: assigned,
            sequenceName: "Song A",
            timecodeName: "Song A TC",
            pluginName: "Song A",
            startFrames: 0,
            lengthFrames: 7_500,
            framerate: .fps25
        ),
        ExportSpec(
            name: "no executor omits the timecode Object and the At Exec command",
            cues: [MA2GoldenInput.cue(1, "Top", at: 1)],
            target: unassigned,
            sequenceName: "Song B",
            timecodeName: "Song B TC",
            pluginName: "Song B",
            startFrames: 0,
            lengthFrames: 900,
            framerate: .fps30
        ),
        ExportSpec(
            name: "escaping, fades, notes and disagreeing number and time order",
            cues: [
                // Number 3 but earliest in time: the timecode events run in time
                // order while carrying the number-ordered sequence index.
                MA2GoldenInput.cue(3, "Third <&>", at: 1, notes: "note & \"quote\""),
                MA2GoldenInput.cue(1, "", at: 9, fadeIn: 2.5),
                MA2GoldenInput.cue(2.5, "Middle 'apostrophe'", at: 5, fadeIn: 0.1 + 0.2, fadeOut: 1.25)
            ],
            target: assigned,
            sequenceName: "A & B <\"C\">",
            timecodeName: "TC & More",
            pluginName: "Set/One:Two\\Three",
            startFrames: 108_000,
            lengthFrames: 1_800,
            framerate: .fps30drop
        ),
        // The timecode generator rounds cue times to frames at its own call site,
        // independent of `MA2TrigTime`, so it needs its own rounding case. Every
        // other case here lands on a whole frame or an exact midpoint, and
        // `.rounded(.up)` agrees with `.rounded()` on both — only a fraction
        // strictly inside `(0, 0.5)` tells them apart. `0.29 × 25` is 7.2499…;
        // `0.5 × 25` is exactly 12.5, which separates away-from-zero (13) from
        // banker's (12) and from truncation (12).
        ExportSpec(
            name: "off-grid cue times snap to the nearest frame, not the next",
            cues: [MA2GoldenInput.cue(1, "Nearest down", at: 0.29), MA2GoldenInput.cue(2, "Midpoint up", at: 0.5)],
            target: assigned,
            sequenceName: "Song C",
            timecodeName: "Song C TC",
            pluginName: "Song C",
            startFrames: 0,
            lengthFrames: 750,
            framerate: .fps25
        ),
        ExportSpec(
            name: "an apostrophe in a name reaches the lua literal through a Label command",
            cues: [MA2GoldenInput.cue(1.0025, "Don't Stop", at: 0.75)],
            target: assigned,
            sequenceName: "Don't Stop",
            timecodeName: "Don't Stop TC",
            pluginName: "Don't Stop",
            startFrames: 0,
            lengthFrames: 600,
            framerate: .fps24
        )
    ]

    /// Lossless line transport: rejoining with `"\n"` reproduces the original
    /// exactly, including a trailing `\r` on CRLF content.
    private static func lines(_ text: String) -> [String] {
        text.components(separatedBy: "\n")
    }

    private static func artifacts(for spec: ExportSpec) -> MA2ExportGoldenVector.Artifacts {
        let plan = MA2PushPlanner.plan(
            cues: MA2GoldenInput.cues(spec.cues),
            target: MA2GoldenInput.target(spec.target),
            sequenceName: spec.sequenceName,
            timecodeName: spec.timecodeName,
            startTimecodeFrames: spec.startFrames,
            lengthFrames: spec.lengthFrames,
            framerate: spec.framerate,
            showfile: showfile,
            datetime: datetime
        )
        let bundle = MA2PluginGenerator.bundle(plan: plan, pluginName: spec.pluginName, datetime: datetime)
        return .init(
            sequenceFilename: plan.sequenceUpload.filename,
            sequenceXML: lines(plan.sequenceUpload.xml),
            timecodeFilename: plan.timecodeUpload.filename,
            timecodeXML: lines(plan.timecodeUpload.xml),
            commands: plan.commands,
            luaFilename: bundle.luaFilename,
            lua: lines(bundle.lua),
            manifestFilename: bundle.manifestFilename,
            manifestXML: lines(bundle.manifestXML)
        )
    }

    static func make() -> MA2ExportGoldenVector {
        MA2ExportGoldenVector(
            contract: "ma2-export",
            version: 1,
            note: "macOS-generated golden vectors for the four OnlyCue grandMA2 export "
                + "artifacts (MA2PushPlanner's sequence XML, timecode XML and command list, "
                + "plus MA2PluginGenerator's Lua plugin and manifest XML). The C# "
                + "OnlyCue.Core re-implementation must reproduce all four byte for byte. "
                + "Each artifact is an array of lines: join with \\n to recover the file. "
                + "datetime is a fixed literal, never a live clock. Cues are identified by "
                + "index. To regenerate after a deliberate change, delete "
                + "golden/ma2-export-v1.json and re-run the test suite.",
            cases: specs.map { spec in
                .init(
                    name: spec.name,
                    cues: spec.cues,
                    target: spec.target,
                    sequenceName: spec.sequenceName,
                    timecodeName: spec.timecodeName,
                    pluginName: spec.pluginName,
                    startTimecodeFrames: spec.startFrames,
                    lengthFrames: spec.lengthFrames,
                    framerate: spec.framerate.rawValue,
                    showfile: showfile,
                    datetime: datetime,
                    expect: artifacts(for: spec)
                )
            }
        )
    }

    static func encoded(_ vector: MA2ExportGoldenVector) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(vector)
    }
}

// MARK: - Tests

final class MA2ExportGoldenVectorTests: XCTestCase {

    private func goldenURL() throws -> URL {
        try repoRoot().appendingPathComponent("golden", isDirectory: true)
            .appendingPathComponent("ma2-export-v1.json")
    }

    /// Independent correctness pins, hand-computed from the documented rules, so a
    /// wrong Swift implementation fails here rather than baking a wrong "golden".
    func test_knownValues() {
        XCTAssertEqual(
            MA2SequenceXMLGenerator.escape("a & b < c > d \" e ' f"),
            "a &amp; b &lt; c &gt; d &quot; e ' f",
            "the apostrophe is deliberately not escaped — XmlWriter would escape it"
        )

        // Plugin filenames replace `/`, `\` and `:` only; spaces and apostrophes stay.
        let plan = MA2PushPlan(
            sequenceUpload: .init(filename: "onlycue_seq_7.xml", xml: "<MA/>"),
            timecodeUpload: .init(filename: "onlycue_tc_3.xml", xml: "<MA/>"),
            commands: ["Label Sequence 7 \"Don't Stop\""]
        )
        let bundle = MA2PluginGenerator.bundle(plan: plan, pluginName: "Set/One:Two\\Three", datetime: "D")
        XCTAssertEqual(bundle.luaFilename, "OnlyCue_Set_One_Two_Three_PLUGIN.lua")
        XCTAssertEqual(bundle.manifestFilename, "OnlyCue_Set_One_Two_Three.xml")
        // The apostrophe is backslash-escaped for the Lua single-quoted literal.
        XCTAssertTrue(
            bundle.lua.contains(#"CMD('Label Sequence 7 "Don\'t Stop"')"#),
            "expected an escaped apostrophe in the Lua command, got:\n\(bundle.lua)"
        )
        // XML goes into a level-2 long bracket by default.
        XCTAssertTrue(bundle.lua.contains("f:write([==[<MA/>]==])"), bundle.lua)
    }

    /// Drift guard + bootstrap, matching the M1a/M1b generators. A missing file is
    /// written and the test fails, so a new contract is committed and reviewed
    /// rather than silently accepted in CI.
    func test_committedVectors_matchCurrentSwiftOutput() throws {
        let url = try goldenURL()
        let generated = try MA2ExportGolden.encoded(MA2ExportGolden.make())
        guard FileManager.default.fileExists(atPath: url.path) else {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try generated.write(to: url)
            return XCTFail("golden/ma2-export-v1.json was missing — generated it from the "
                + "Swift implementation. Commit the file and re-run. (To regenerate after a "
                + "deliberate change, delete the file first.)")
        }

        let committed = try JSONDecoder().decode(
            MA2ExportGoldenVector.self, from: Data(contentsOf: url)
        )
        XCTAssertEqual(
            committed,
            MA2ExportGolden.make(),
            "golden/ma2-export-v1.json drifted from the Swift implementation. If the change "
                + "was intentional, delete the file and re-run to regenerate, review the diff, "
                + "and update the C# OnlyCue.Core to match."
        )
    }
}
