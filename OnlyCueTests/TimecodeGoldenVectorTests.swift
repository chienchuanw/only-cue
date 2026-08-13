import XCTest
@testable import OnlyCue

// The cross-platform golden-vector contract for `Timecode` math (epic #728, M0).
// macOS is the source of truth: it emits `golden/timecode-v1.json`; the future
// C# `OnlyCue.Core` re-implementation must reproduce every case byte-for-byte
// (verified on Windows CI). This file both *generates* the vectors (from the
// Swift implementation) and *guards* the committed file against drift.
//
// The drop-frame (`30df`) cases are the point of the exercise — the counting
// rule that skips frame numbers 00/01 at the top of every minute except every
// tenth is exactly the kind of subtle logic that silently diverges between two
// hand-maintained implementations.

// MARK: - Contract model (mirrored by the C# verifier's DTO)

struct TimecodeGoldenVector: Codable, Equatable {
    let contract: String   // "timecode"
    let version: Int       // 1
    let note: String
    let cases: [Case]

    struct Case: Codable, Equatable {
        let op: String     // "fromFrameCount" | "fromTotalSeconds" | "parse"
        let rate: String   // SMPTEFramerate.rawValue: "24" | "25" | "30" | "30df"
        let input: Input
        let expect: Expect
    }

    struct Input: Codable, Equatable {
        var frameCount: Int?
        var totalSeconds: Double?
        var string: String?
    }

    struct Expect: Codable, Equatable {
        var valid: Bool
        var hours: Int?
        var minutes: Int?
        var seconds: Int?
        var frames: Int?
        var display: String?
        var frameCount: Int?
    }
}

// MARK: - Generator (the Swift implementation IS the contract source of truth)

enum TimecodeGolden {

    static let allRates: [SMPTEFramerate] = [.fps24, .fps25, .fps30, .fps30drop]

    /// Frame-count inputs per rate. Common boundaries plus, for drop-frame, the
    /// minute / tenth-minute rollovers where the skip rule bites.
    static func frameCountInputs(for rate: SMPTEFramerate) -> [Int] {
        let fps = rate.framesPerSecond
        var inputs = [
            0, 1, fps - 1, fps,            // sub-second + 1s
            fps * 60 - 1, fps * 60,        // 1 minute
            fps * 60 * 10,                 // 10 minutes
            fps * 3600,                    // 1 hour
            fps * 3600 + fps * 61 + 7      // an arbitrary interior point
        ]
        if rate.isDropFrame {
            // 1798 = 30*60 − 2 → 00:01:00;02 (2 frames skipped at minute 1).
            // 17982 = 30*600 − 18 → 00:10:00;00 (no skip at the tenth minute).
            inputs += [1796, 1797, 1798, 1799, 17981, 17982, 17983]
        }
        // A value past 24:00:00:00 to exercise the day wrap.
        inputs.append(fps * 3600 * 24 + 5)
        return Array(Set(inputs)).sorted()
    }

    /// The `Expect` for a concrete `Timecode`.
    private static func expect(_ tc: Timecode) -> TimecodeGoldenVector.Expect {
        TimecodeGoldenVector.Expect(
            valid: true,
            hours: tc.hours,
            minutes: tc.minutes,
            seconds: tc.seconds,
            frames: tc.frames,
            display: tc.displayString,
            frameCount: tc.frameCount
        )
    }

    private static let invalidExpect = TimecodeGoldenVector.Expect(
        valid: false,
        hours: nil,
        minutes: nil,
        seconds: nil,
        frames: nil,
        display: nil,
        frameCount: nil
    )

    private static func frameCountCases() -> [TimecodeGoldenVector.Case] {
        allRates.flatMap { rate in
            frameCountInputs(for: rate).map { fc in
                TimecodeGoldenVector.Case(
                    op: "fromFrameCount",
                    rate: rate.rawValue,
                    input: .init(frameCount: fc, totalSeconds: nil, string: nil),
                    expect: expect(Timecode(frameCount: fc, rate: rate))
                )
            }
        }
    }

    private static func totalSecondsCases() -> [TimecodeGoldenVector.Case] {
        allRates.flatMap { rate in
            [0.0, 1.0, 1.5, 60.0, 123.456].map { secs in
                TimecodeGoldenVector.Case(
                    op: "fromTotalSeconds",
                    rate: rate.rawValue,
                    input: .init(frameCount: nil, totalSeconds: secs, string: nil),
                    expect: expect(Timecode(totalSeconds: secs, rate: rate))
                )
            }
        }
    }

    private static func parseCases() -> [TimecodeGoldenVector.Case] {
        let inputs: [(String, SMPTEFramerate)] = [
            ("00:00:00:00", .fps24), ("01:02:03:04", .fps24),
            ("10:20:30:12", .fps25), ("23:59:59:29", .fps30),
            ("00:01:00;02", .fps30drop),           // drop-frame punctuation
            ("00:01:00;00", .fps30drop),           // skipped frame → invalid
            ("00:00:00:30", .fps30),               // frame out of range → invalid
            ("nonsense", .fps24)                    // unparseable → invalid
        ]
        return inputs.map { string, rate in
            TimecodeGoldenVector.Case(
                op: "parse",
                rate: rate.rawValue,
                input: .init(frameCount: nil, totalSeconds: nil, string: string),
                expect: Timecode.parse(string, rate: rate).map(expect) ?? invalidExpect
            )
        }
    }

    static func make() -> TimecodeGoldenVector {
        TimecodeGoldenVector(
            contract: "timecode",
            version: 1,
            note: "macOS-generated golden vectors for OnlyCue Timecode math. The C# "
                + "OnlyCue.Core re-implementation must reproduce every case exactly. "
                + "To regenerate after a deliberate Timecode change, delete "
                + "golden/timecode-v1.json and re-run the test suite.",
            cases: frameCountCases() + totalSecondsCases() + parseCases()
        )
    }

    /// Deterministic encoding so the committed file is stable and diff-friendly.
    static func encoded(_ vector: TimecodeGoldenVector) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(vector)
    }
}

// MARK: - Tests

final class TimecodeGoldenVectorTests: XCTestCase {

    private func goldenURL() throws -> URL {
        try repoRoot().appendingPathComponent("golden", isDirectory: true)
            .appendingPathComponent("timecode-v1.json")
    }

    /// Independent correctness pins: hand-computed drop-frame expectations that
    /// don't depend on the generator, so a wrong `Timecode` implementation fails
    /// here rather than silently baking a wrong "golden" value.
    func test_knownDropFrameValues() {
        let df = SMPTEFramerate.fps30drop
        // At exactly 60 s (1800 frames) drop-frame skips frame numbers ;00 and
        // ;01 at the top of minute 1, so the label jumps 00:00:59;29 → 00:01:00;02.
        XCTAssertEqual(Timecode(frameCount: 1799, rate: df).displayString, "00:00:59;29")
        XCTAssertEqual(Timecode(frameCount: 1800, rate: df).displayString, "00:01:00;02")
        // No skip at the tenth minute: 00:10:00;00 is valid; its elapsed frame
        // count is 10*60*30 − 2*(10 − 1) = 17982.
        XCTAssertEqual(Timecode(frameCount: 17982, rate: df).displayString, "00:10:00;00")
        // Round-trip: those components map back to the same frame count.
        XCTAssertEqual(Timecode(hours: 0, minutes: 1, seconds: 0, frames: 2, rate: df)?.frameCount, 1800)
        XCTAssertEqual(Timecode(hours: 0, minutes: 10, seconds: 0, frames: 0, rate: df)?.frameCount, 17982)
        // Non-drop sanity.
        XCTAssertEqual(Timecode(frameCount: 30, rate: .fps30).displayString, "00:00:01:00")
        XCTAssertEqual(Timecode(frameCount: 24, rate: .fps24).displayString, "00:00:01:00")
    }

    /// Drift guard + bootstrap. When the committed file is present it must equal
    /// the current Swift output byte-for-byte (that's the contract the C# core
    /// will verify against). When it is missing — first run, or after a deliberate
    /// `Timecode` change where the dev deleted it to regenerate — it is written
    /// and the test fails, so the new contract is committed and reviewed rather
    /// than silently accepted in CI.
    func test_committedVectors_matchCurrentSwiftOutput() throws {
        let url = try goldenURL()
        let generated = try TimecodeGolden.encoded(TimecodeGolden.make())

        guard FileManager.default.fileExists(atPath: url.path) else {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try generated.write(to: url)
            return XCTFail("golden/timecode-v1.json was missing — generated it from the "
                + "Swift Timecode implementation. Commit the file and re-run. (To "
                + "regenerate after a deliberate Timecode change, delete the file first.)")
        }

        let committed = try JSONDecoder().decode(
            TimecodeGoldenVector.self, from: Data(contentsOf: url)
        )
        XCTAssertEqual(
            committed,
            TimecodeGolden.make(),
            "golden/timecode-v1.json drifted from the Swift Timecode implementation. "
                + "If the change was intentional, delete the file and re-run to regenerate, "
                + "review the diff, and update the C# OnlyCue.Core to match."
        )
    }
}
