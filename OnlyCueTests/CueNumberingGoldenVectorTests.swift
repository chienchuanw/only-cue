import XCTest
@testable import OnlyCue

// The cross-platform golden-vector contract for cue-number assignment (epic #728,
// M1b — vector 3 of the seven in
// `docs/superpowers/specs/2026-09-14-windows-m1-contract-design.md`).
//
// macOS is the source of truth: this file emits `golden/cue-numbering-v1.json`
// from `CueNumberAssignment` + `CueNumberAutoFill`, and the C# `OnlyCue.Core`
// re-implementation must reproduce every case (verified on Windows CI).
//
// The cases worth the effort are the numeric ones. `CueNumberAutoFill` rounds to
// thousandths with Swift's `.rounded()`, which is round-half-**away-from-zero**;
// .NET's `Math.Round(double)` defaults to banker's rounding, so a straight port
// diverges on exact midpoints. It also relies on `sorted(by:)` with an explicit
// original-index tie-break (neither `List.Sort` nor `OrderBy` reproduces that by
// accident) and on `max(by:)`/`min(by:)` keeping the *first* extremum on ties.

// MARK: - Contract model (mirrored by the C# verifier's DTO)

struct CueNumberingGoldenVector: Codable, Equatable {
    let contract: String   // "cue-numbering"
    let version: Int       // 1
    let note: String
    let insertion: [InsertionCase]
    let autoFill: [AutoFillCase]

    /// Only the two fields either algorithm reads. Cues are identified by their
    /// position in this array, so the vector mints no UUIDs.
    struct CueInput: Codable, Equatable {
        let time: GoldenDouble
        let cueNumber: GoldenDouble?
    }

    struct InsertionCase: Codable, Equatable {
        let name: String
        let cues: [CueInput]
        let atTime: GoldenDouble
        let expect: GoldenDouble
    }

    struct AutoFillCase: Codable, Equatable {
        let name: String
        let cues: [CueInput]
        /// The nil-numbered cues that received a number, by input index. A
        /// nil-numbered cue absent from this list is expected to stay nil —
        /// that is a real outcome (`pick` returns nil when the interval holds no
        /// unique thousandth), not a gap in the vector.
        let expect: [Assignment]
    }

    struct Assignment: Codable, Equatable {
        let index: Int
        let number: GoldenDouble
    }
}

// MARK: - Case specifications

/// One `CueNumberAssignment.next` call. A struct rather than a tuple so the
/// table below stays readable (and within SwiftLint's tuple-arity rule).
private struct InsertionSpec {
    let name: String
    let cues: [(time: Double, number: Double?)]
    let at: Double

    init(_ name: String, _ cues: [(time: Double, number: Double?)], at: Double) {
        self.name = name
        self.cues = cues
        self.at = at
    }
}

// MARK: - Generator (the Swift implementation IS the contract source of truth)

enum CueNumberingGolden {

    /// Deterministic, total, and collision-free for the case sizes here — so the
    /// vector's index mapping is reproducible without minting random UUIDs.
    private static func identifier(_ index: Int) -> UUID {
        UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, UInt8(index >> 8), UInt8(index & 0xFF)))
    }

    private static func cues(_ spec: [(time: Double, number: Double?)]) -> [Cue] {
        spec.enumerated().map { index, entry in
            Cue(
                id: identifier(index),
                typeID: identifier(0),
                cueNumber: entry.number,
                name: "",
                time: entry.time,
                notes: "",
                fadeTime: .zero
            )
        }
    }

    private static func inputs(_ spec: [(time: Double, number: Double?)]) -> [CueNumberingGoldenVector.CueInput] {
        spec.map { .init(time: GoldenDouble($0.time), cueNumber: GoldenDouble($0.number)) }
    }

    // MARK: Insertion

    /// Every branch of `CueNumberAssignment.next`, plus the two tie cases where
    /// Swift's `max(by:)`/`min(by:)` keep the first extremum.
    private static let insertionSpecs: [InsertionSpec] = [
        .init("empty list falls back to 1", [], at: 5),
        .init("no numbered cues falls back to 1", [(1, nil), (2, nil)], at: 1.5),
        .init("before the first numbered cue steps down", [(10, 5)], at: 1),
        .init("after the last numbered cue steps up", [(1, 3)], at: 10),
        .init("between two numbered cues takes the midpoint", [(1, 1), (3, 2)], at: 2),
        .init("the earlier neighbour boundary is inclusive", [(1, 1), (3, 2)], at: 3),
        .init("unnumbered cues are skipped when picking neighbours", [(1, nil), (2, 1), (5, nil), (9, 4)], at: 6),
        .init("an equal-time tie on the earlier side keeps the first", [(2, 1), (2, 3)], at: 5),
        .init("an equal-time tie on the later side keeps the first", [(2, 1), (8, 5), (8, 9)], at: 4),
        .init("fractional neighbours halve exactly", [(1, 0.5), (2, 0.75)], at: 1.5),
        .init("stepping down below 1 is not clamped", [(5, 0.5)], at: 1)
    ]

    private static func insertionCases() -> [CueNumberingGoldenVector.InsertionCase] {
        insertionSpecs.map { spec in
            CueNumberingGoldenVector.InsertionCase(
                name: spec.name,
                cues: inputs(spec.cues),
                atTime: GoldenDouble(spec.at),
                expect: GoldenDouble(CueNumberAssignment.next(forInsertionAt: spec.at, in: cues(spec.cues)))
            )
        }
    }

    // MARK: Auto-fill

    private static let autoFillSpecs: [(name: String, cues: [(time: Double, number: Double?)])] = [
        ("empty list assigns nothing", []),
        ("a fully numbered list assigns nothing", [(1, 1), (2, 2)]),
        ("an integer fits the gap", [(1, 1), (2, nil), (3, 3)]),
        ("no integer fits so it steps by 0.1", [(1, 1), (2, nil), (3, 2)]),
        ("consecutive gaps stay strictly increasing", [(1, 1), (2, nil), (3, nil), (4, 2)]),
        ("an open lower bound starts at 1", [(1, nil), (2, 5)]),
        ("an open upper bound steps up from the lower", [(1, 3), (2, nil)]),
        ("a wholly unnumbered list counts from 1", [(1, nil), (2, nil)]),
        ("a tight upper bound falls back to subdivision", [(1, 1), (2, nil), (3, 1.05)]),
        ("a one-thousandth gap holds no unique value", [(1, 1), (2, nil), (3, 1.001)]),
        ("a sub-thousandth gap holds no unique value", [(1, nil), (2, 0.0005)]),
        // The two cases that separate Swift's `.rounded()` from .NET's default
        // banker's rounding. Both land on an exact thousandths midpoint: the
        // subdivision candidate (0.001+0.004)/2 → 2.5, and the seed key
        // 0.0025 → 2.5. Away-from-zero yields 0.003 / a used-key of 3; banker's
        // yields 0.002 / 2, which the C# verifier must not be free to produce.
        ("a midpoint candidate rounds away from zero", [(1, 0.001), (2, nil), (3, 0.004)]),
        ("a midpoint existing number seeds the used set away from zero", [(1, 0.0025), (2, nil), (3, 0.004)]),
        ("numbers running backwards against time assign nothing", [(1, 5), (2, nil), (3, 2)]),
        ("an integer already used out of time order is skipped", [(1, 1), (2, nil), (3, 5), (4, 2)]),
        ("equal times are ordered by original index", [(2, nil), (2, 1)])
    ]

    private static func autoFillCases() -> [CueNumberingGoldenVector.AutoFillCase] {
        autoFillSpecs.map { spec in
            let built = cues(spec.cues)
            let assigned = CueNumberAutoFill.assignments(for: built)
            let expect = built.enumerated().compactMap { index, cue in
                assigned[cue.id].map {
                    CueNumberingGoldenVector.Assignment(index: index, number: GoldenDouble($0))
                }
            }
            return CueNumberingGoldenVector.AutoFillCase(
                name: spec.name,
                cues: inputs(spec.cues),
                expect: expect
            )
        }
    }

    static func make() -> CueNumberingGoldenVector {
        CueNumberingGoldenVector(
            contract: "cue-numbering",
            version: 1,
            note: "macOS-generated golden vectors for OnlyCue cue-number assignment "
                + "(CueNumberAssignment.next and CueNumberAutoFill.assignments). The C# "
                + "OnlyCue.Core re-implementation must reproduce every case exactly. "
                + "Doubles are round-trip-exact decimal strings; compare the parsed "
                + "IEEE-754 values, not the text. Cues are identified by index. To "
                + "regenerate after a deliberate change, delete "
                + "golden/cue-numbering-v1.json and re-run the test suite.",
            insertion: insertionCases(),
            autoFill: autoFillCases()
        )
    }

    /// Deterministic encoding so the committed file is stable and diff-friendly.
    static func encoded(_ vector: CueNumberingGoldenVector) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(vector)
    }
}

// MARK: - Tests

final class CueNumberingGoldenVectorTests: XCTestCase {

    private func goldenURL() throws -> URL {
        try repoRoot().appendingPathComponent("golden", isDirectory: true)
            .appendingPathComponent("cue-numbering-v1.json")
    }

    private func cue(time: TimeInterval, number: Double?) -> Cue {
        Cue(id: UUID(), typeID: UUID(), cueNumber: number, name: "", time: time, notes: "", fadeTime: .zero)
    }

    /// Independent correctness pins, hand-computed from the documented rules, so
    /// a wrong Swift implementation fails here rather than silently baking a
    /// wrong "golden" value.
    func test_knownValues() {
        XCTAssertEqual(CueNumberAssignment.next(forInsertionAt: 5, in: []), 1.0)
        XCTAssertEqual(
            CueNumberAssignment.next(forInsertionAt: 2, in: [cue(time: 1, number: 1), cue(time: 3, number: 2)]),
            1.5
        )
        XCTAssertEqual(CueNumberAssignment.next(forInsertionAt: 1, in: [cue(time: 5, number: 0.5)]), -0.5)

        // [1, _, 3] → the whole number fits.
        let integerGap = [cue(time: 1, number: 1), cue(time: 2, number: nil), cue(time: 3, number: 3)]
        XCTAssertEqual(CueNumberAutoFill.assignments(for: integerGap)[integerGap[1].id], 2.0)

        // [1, _, 2] → no whole number fits, so a 0.1 step from the lower bound.
        let tightGap = [cue(time: 1, number: 1), cue(time: 2, number: nil), cue(time: 3, number: 2)]
        XCTAssertEqual(CueNumberAutoFill.assignments(for: tightGap)[tightGap[1].id], 1.1)

        // [1, _, 1.001] → the interval holds no *unique* thousandth, so the cue is
        // deliberately left nil for the MA2 pre-flight to report.
        let noRoom = [cue(time: 1, number: 1), cue(time: 2, number: nil), cue(time: 3, number: 1.001)]
        XCTAssertNil(CueNumberAutoFill.assignments(for: noRoom)[noRoom[1].id])

        // [0.001, _, 0.004] → subdivision midpoints at exactly 2.5 thousandths.
        // `.rounded()` is away-from-zero, so 0.003; banker's would give 0.002.
        let midCandidate = [cue(time: 1, number: 0.001), cue(time: 2, number: nil), cue(time: 3, number: 0.004)]
        XCTAssertEqual(CueNumberAutoFill.assignments(for: midCandidate)[midCandidate[1].id], 0.003)

        // Same interval, but 0.0025 seeds the used set. Away-from-zero keys it to
        // 3, which blocks 0.003 and leaves the cue nil; banker's would key it to 2
        // and wrongly hand out 0.003.
        let midSeed = [cue(time: 1, number: 0.0025), cue(time: 2, number: nil), cue(time: 3, number: 0.004)]
        XCTAssertNil(CueNumberAutoFill.assignments(for: midSeed)[midSeed[1].id])
    }

    /// Drift guard + bootstrap, matching `TimecodeGoldenVectorTests`. A missing
    /// file is written and the test fails, so a new contract is committed and
    /// reviewed rather than silently accepted in CI.
    func test_committedVectors_matchCurrentSwiftOutput() throws {
        let url = try goldenURL()
        let generated = try CueNumberingGolden.encoded(CueNumberingGolden.make())
        guard FileManager.default.fileExists(atPath: url.path) else {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try generated.write(to: url)
            return XCTFail("golden/cue-numbering-v1.json was missing — generated it from the "
                + "Swift implementation. Commit the file and re-run. (To regenerate after a "
                + "deliberate change, delete the file first.)")
        }

        let committed = try JSONDecoder().decode(
            CueNumberingGoldenVector.self, from: Data(contentsOf: url)
        )
        XCTAssertEqual(
            committed,
            CueNumberingGolden.make(),
            "golden/cue-numbering-v1.json drifted from the Swift implementation. If the "
                + "change was intentional, delete the file and re-run to regenerate, review "
                + "the diff, and update the C# OnlyCue.Core to match."
        )
    }
}
