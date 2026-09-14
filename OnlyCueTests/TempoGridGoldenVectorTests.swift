import XCTest
@testable import OnlyCue

// The cross-platform golden-vector contract for the derived tempo grid (epic
// #728, M1b — vector 7 of the seven in
// `docs/superpowers/specs/2026-09-14-windows-m1-contract-design.md`).
//
// macOS is the source of truth: this file emits `golden/tempo-grid-v1.json` from
// `DerivedTempoGrid`, and the C# `OnlyCue.Core` re-implementation must reproduce
// every case (verified on Windows CI).
//
// Three things here diverge silently under a naive port:
//   - `.rounded()` is round-half-**away-from-zero**; .NET's `Math.Round(double)`
//     rounds half-to-even. A point query landing exactly between two beats
//     resolves differently.
//   - `.rounded(.up)` / `.rounded(.down)` are ceiling/floor, *not* truncation.
//     They differ for a range starting before the segment anchor, so a C# `(int)`
//     cast is wrong there.
//   - Beat times must be recomputed as `anchor + index * step`, not accumulated,
//     or the low bits drift and bitwise comparison fails.

// MARK: - Contract model (mirrored by the C# verifier's DTO)

struct TempoGridGoldenVector: Codable, Equatable {
    let contract: String   // "tempo-grid"
    let version: Int       // 1
    let note: String
    let cases: [Case]

    /// The three fields `DerivedTempoGrid.from(cues:)` reads. Values are the
    /// *raw* inputs — the C# side must apply `Cue.Clamped()` first, exactly as
    /// Swift's clamping `Cue.init` does, before deriving the grid.
    struct CueInput: Codable, Equatable {
        let time: GoldenDouble
        let bpm: GoldenDouble?
        let beatsPerBar: Int?
    }

    struct SegmentOutput: Codable, Equatable {
        let startSeconds: GoldenDouble
        let bpm: GoldenDouble
        let beatsPerBar: Int
        let beatDuration: GoldenDouble
        let barDuration: GoldenDouble
    }

    struct Beat: Codable, Equatable {
        let time: GoldenDouble
        let isDownbeat: Bool
    }

    /// `beatTimes(in:itemDuration:)` and `barTimes(in:itemDuration:)` over one
    /// closed range. Bars are derived from beats, so pinning both in one query
    /// also pins that relationship.
    struct RangeQuery: Codable, Equatable {
        let lowerBound: GoldenDouble
        let upperBound: GoldenDouble
        let beats: [Beat]
        let bars: [GoldenDouble]
    }

    /// `nearestBeat` / `nearestBar` at one instant. `null` means "no segment
    /// covers this point", which is a real result, not a missing case.
    struct PointQuery: Codable, Equatable {
        let seconds: GoldenDouble
        let nearestBeat: GoldenDouble?
        let nearestBar: GoldenDouble?
    }

    struct Case: Codable, Equatable {
        let name: String
        let cues: [CueInput]
        let itemDuration: GoldenDouble
        let segments: [SegmentOutput]
        let ranges: [RangeQuery]
        let points: [PointQuery]
    }
}

// MARK: - Case specifications

/// A cue as the grid sees it — structs rather than tuples so the tables below
/// stay readable (and within SwiftLint's tuple-arity rule).
private struct TempoCueSpec {
    let time: TimeInterval
    let bpm: Double?
    let beatsPerBar: Int?

    init(_ time: TimeInterval, _ bpm: Double?, _ beatsPerBar: Int?) {
        self.time = time
        self.bpm = bpm
        self.beatsPerBar = beatsPerBar
    }
}

/// One grid plus the queries run against it. Kept separate from the generator so
/// the interesting part — the inputs — reads as a table.
private struct TempoGridCaseSpec {
    let name: String
    let cues: [TempoCueSpec]
    let itemDuration: TimeInterval
    let ranges: [(lower: TimeInterval, upper: TimeInterval)]
    let points: [TimeInterval]
}

private let tempoGridSpecs: [TempoGridCaseSpec] = [
    TempoGridCaseSpec(
        name: "no bpm cues yields an empty grid",
        cues: [.init(0, nil, nil), .init(3, nil, 4)],
        itemDuration: 10,
        ranges: [(0, 10)],
        points: [0, 5]
    ),
    TempoGridCaseSpec(
        name: "a single 120 bpm segment runs to the item end",
        cues: [.init(0, 120, 4)],
        itemDuration: 10,
        // The third range starts before the anchor, which is where `.rounded(.up)`
        // must be a ceiling rather than a truncation.
        ranges: [(0, 10), (1.2, 3.3), (-1, 1)],
        // 0.25 is exactly between two beats — the round-half-away-from-zero pin.
        points: [0.25, 0.74, 0.76, 0.9, 10, 20, -5]
    ),
    TempoGridCaseSpec(
        name: "beatsPerBar is inherited from the previous segment",
        cues: [.init(0, 120, 3), .init(4, 90, nil)],
        itemDuration: 12,
        ranges: [(0, 12)],
        points: [3.9, 4, 4.1]
    ),
    TempoGridCaseSpec(
        name: "beatsPerBar defaults to 4 when no cue sets it",
        cues: [.init(0, 100, nil)],
        itemDuration: 6,
        ranges: [(0, 6)],
        points: [1.7]
    ),
    TempoGridCaseSpec(
        name: "bpm and meter are clamped to their legal ranges",
        cues: [.init(0, 500, 99), .init(3, 5, 0)],
        itemDuration: 6,
        ranges: [(0, 6)],
        points: [1, 4]
    ),
    TempoGridCaseSpec(
        name: "a negative cue time anchors the segment at zero",
        cues: [.init(-2, 120, 4)],
        itemDuration: 4,
        ranges: [(-3, 4)],
        points: [-1, 0, 1]
    ),
    TempoGridCaseSpec(
        name: "co-located bpm cues de-duplicate last-wins",
        cues: [.init(2, 120, 4), .init(2, 90, 3)],
        itemDuration: 8,
        ranges: [(0, 8)],
        points: [2, 5]
    ),
    TempoGridCaseSpec(
        name: "a segment boundary beat belongs to the later segment",
        cues: [.init(0, 120, 4), .init(2, 240, 4)],
        itemDuration: 4,
        ranges: [(0, 4), (1.9, 2.1)],
        points: [1.9, 2, 2.1]
    ),
    TempoGridCaseSpec(
        name: "nearest prefers the next segment start when it is closer",
        cues: [.init(0, 120, 4), .init(3.1, 120, 4)],
        itemDuration: 6,
        ranges: [(2.5, 3.5)],
        points: [3.06, 2.9]
    ),
    TempoGridCaseSpec(
        name: "a point before the first segment has no nearest grid line",
        cues: [.init(5, 120, 4)],
        itemDuration: 10,
        ranges: [(0, 4), (0, 10)],
        points: [1, 4.999, 5]
    ),
    TempoGridCaseSpec(
        name: "bpm cues are sorted by time regardless of input order",
        cues: [.init(6, 90, nil), .init(2, 120, 3)],
        itemDuration: 10,
        ranges: [(0, 10)],
        points: [7]
    ),
    TempoGridCaseSpec(
        name: "a non-terminating beat duration stresses float determinism",
        cues: [.init(0, 133, 5)],
        itemDuration: 5,
        ranges: [(0, 5), (1.1, 2.2)],
        points: [0.3, 2.7, 4.9]
    )
]

// MARK: - Generator (the Swift implementation IS the contract source of truth)

enum TempoGridGolden {

    private static func identifier(_ index: Int) -> UUID {
        UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, UInt8(index >> 8), UInt8(index & 0xFF)))
    }

    private static func cues(_ spec: TempoGridCaseSpec) -> [Cue] {
        spec.cues.enumerated().map { index, entry in
            Cue(
                id: identifier(index),
                typeID: identifier(0),
                cueNumber: nil,
                name: "",
                time: entry.time,
                notes: "",
                fadeTime: .zero,
                bpm: entry.bpm,
                beatsPerBar: entry.beatsPerBar
            )
        }
    }

    private static func segments(_ grid: DerivedTempoGrid) -> [TempoGridGoldenVector.SegmentOutput] {
        grid.segments.map {
            .init(
                startSeconds: GoldenDouble($0.startSeconds),
                bpm: GoldenDouble($0.bpm),
                beatsPerBar: $0.beatsPerBar,
                beatDuration: GoldenDouble($0.beatDuration),
                barDuration: GoldenDouble($0.barDuration)
            )
        }
    }

    private static func ranges(_ spec: TempoGridCaseSpec, _ grid: DerivedTempoGrid) -> [TempoGridGoldenVector.RangeQuery] {
        spec.ranges.map { bounds in
            let range = bounds.lower...bounds.upper
            let beats = grid.beatTimes(in: range, itemDuration: spec.itemDuration)
            return .init(
                lowerBound: GoldenDouble(bounds.lower),
                upperBound: GoldenDouble(bounds.upper),
                beats: beats.map { .init(time: GoldenDouble($0.time), isDownbeat: $0.isDownbeat) },
                bars: grid.barTimes(in: range, itemDuration: spec.itemDuration).map { GoldenDouble($0) }
            )
        }
    }

    private static func points(_ spec: TempoGridCaseSpec, _ grid: DerivedTempoGrid) -> [TempoGridGoldenVector.PointQuery] {
        spec.points.map { seconds in
            .init(
                seconds: GoldenDouble(seconds),
                nearestBeat: GoldenDouble(grid.nearestBeat(toSeconds: seconds, itemDuration: spec.itemDuration)),
                nearestBar: GoldenDouble(grid.nearestBar(toSeconds: seconds, itemDuration: spec.itemDuration))
            )
        }
    }

    static func make() -> TempoGridGoldenVector {
        TempoGridGoldenVector(
            contract: "tempo-grid",
            version: 1,
            note: "macOS-generated golden vectors for OnlyCue's DerivedTempoGrid. The C# "
                + "OnlyCue.Core re-implementation must reproduce every case exactly. Cue "
                + "inputs are raw: apply the Cue clamping (bpm 20…400, beatsPerBar 1…16, "
                + "non-finite bpm to null) before deriving. Doubles are round-trip-exact "
                + "decimal strings; compare the parsed IEEE-754 values, not the text. To "
                + "regenerate after a deliberate change, delete golden/tempo-grid-v1.json "
                + "and re-run the test suite.",
            cases: tempoGridSpecs.map { spec in
                let grid = DerivedTempoGrid.from(cues: cues(spec))
                return TempoGridGoldenVector.Case(
                    name: spec.name,
                    cues: spec.cues.map {
                        .init(time: GoldenDouble($0.time), bpm: GoldenDouble($0.bpm), beatsPerBar: $0.beatsPerBar)
                    },
                    itemDuration: GoldenDouble(spec.itemDuration),
                    segments: segments(grid),
                    ranges: ranges(spec, grid),
                    points: points(spec, grid)
                )
            }
        )
    }

    /// Deterministic encoding so the committed file is stable and diff-friendly.
    static func encoded(_ vector: TempoGridGoldenVector) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(vector)
    }
}

// MARK: - Tests

final class TempoGridGoldenVectorTests: XCTestCase {

    private func goldenURL() throws -> URL {
        try repoRoot().appendingPathComponent("golden", isDirectory: true)
            .appendingPathComponent("tempo-grid-v1.json")
    }

    private func grid(_ spec: [TempoCueSpec]) -> DerivedTempoGrid {
        DerivedTempoGrid.from(cues: spec.map {
            Cue(
                id: UUID(),
                typeID: UUID(),
                cueNumber: nil,
                name: "",
                time: $0.time,
                notes: "",
                fadeTime: .zero,
                bpm: $0.bpm,
                beatsPerBar: $0.beatsPerBar
            )
        })
    }

    /// Independent correctness pins, hand-computed from the documented rules, so
    /// a wrong Swift implementation fails here rather than silently baking a
    /// wrong "golden" value.
    func test_knownValues() {
        // 120 bpm ⇒ a beat every 0.5 s, a downbeat every 4 beats.
        let simple = grid([.init(0, 120, 4)])
        let beats = simple.beatTimes(in: 0...2, itemDuration: 10)
        XCTAssertEqual(beats.map(\.time), [0, 0.5, 1.0, 1.5, 2.0])
        // A 4/4 bar at 120 bpm is 2 s, so the range's closing beat (index 4) opens
        // bar 2 — consistent with `barTimes` below listing 2.0.
        XCTAssertEqual(beats.map(\.isDownbeat), [true, false, false, false, true])
        XCTAssertEqual(simple.barTimes(in: 0...5, itemDuration: 10), [0, 2, 4])

        // Exactly half-way between beats 0 and 1 — away-from-zero rounding picks
        // the later beat. Banker's rounding would pick 0.0 and be wrong.
        XCTAssertEqual(simple.nearestBeat(toSeconds: 0.25, itemDuration: 10), 0.5)

        // The 2 s boundary belongs to the *later* segment, so the first segment
        // contributes 0/0.5/1.0/1.5 and the second starts the run at 2.0.
        let split = grid([.init(0, 120, 4), .init(2, 240, 4)])
        XCTAssertEqual(split.beatTimes(in: 0...2, itemDuration: 4).map(\.time), [0, 0.5, 1.0, 1.5, 2.0])
        XCTAssertEqual(split.beatTimes(in: 1.9...2.1, itemDuration: 4).map(\.time), [2.0])

        // Before the first segment there is no grid line to snap to.
        XCTAssertNil(grid([.init(5, 120, 4)]).nearestBeat(toSeconds: 1, itemDuration: 10))

        // Co-located bpm cues collapse, last one wins.
        XCTAssertEqual(grid([.init(2, 120, 4), .init(2, 90, 3)]).segments.count, 1)
        XCTAssertEqual(grid([.init(2, 120, 4), .init(2, 90, 3)]).segments.first?.bpm, 90)
    }

    /// Drift guard + bootstrap, matching `TimecodeGoldenVectorTests`. A missing
    /// file is written and the test fails, so a new contract is committed and
    /// reviewed rather than silently accepted in CI.
    func test_committedVectors_matchCurrentSwiftOutput() throws {
        let url = try goldenURL()
        let generated = try TempoGridGolden.encoded(TempoGridGolden.make())
        guard FileManager.default.fileExists(atPath: url.path) else {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try generated.write(to: url)
            return XCTFail("golden/tempo-grid-v1.json was missing — generated it from the "
                + "Swift DerivedTempoGrid. Commit the file and re-run. (To regenerate after "
                + "a deliberate change, delete the file first.)")
        }

        let committed = try JSONDecoder().decode(
            TempoGridGoldenVector.self, from: Data(contentsOf: url)
        )
        XCTAssertEqual(
            committed,
            TempoGridGolden.make(),
            "golden/tempo-grid-v1.json drifted from the Swift DerivedTempoGrid. If the "
                + "change was intentional, delete the file and re-run to regenerate, review "
                + "the diff, and update the C# OnlyCue.Core to match."
        )
    }
}
