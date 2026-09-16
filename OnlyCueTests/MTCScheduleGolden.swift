import Foundation
@testable import OnlyCue

// The cross-platform golden-vector contract for the **MTC scheduling layer**
// (epic #728, M3 slice 2). macOS is the source of truth: it emits
// `golden/mtc-schedule-v1.json`; the C# `OnlyCue.Core` re-implementation must
// reproduce every case exactly (verified on Windows CI).
//
// Slice 1 (`golden/mtc-wire-v1.json`) pinned the bytes. This contract pins how
// a host-clock window selects which of them are due:
//
// - `cadence`          — `MTCSchedule.ticksPerQuarterFrame`.
// - `sequenceTimecode` — the two-frames-per-sequence advance and its clamp.
// - `quarterFrame`     — one message's byte and host timestamp.
// - `batch`            — the degenerate windows (empty, inverted, pre-anchor).
// - `batchChain`       — **the load-bearing op.** A chain of half-open windows
//                        where each `until` is the next `from`, plus the batch
//                        over the whole span. Both sides assert
//                        `concat(windows) == combined`, so a message dropped at
//                        a seam and a message duplicated at one fail differently.
//
// Why `batchChain` matters: `quarterFrameIndex(atOrAfter:)` quantises to a
// microsecond of a quarter-frame before taking the ceiling, so a timestamp this
// type itself emitted maps back to its own index instead of the next one.
// Simulated over the first 200 messages with boundaries on emitted timestamps,
// a port that dropped that quantise loses 74/200 at 24 fps and 66/200 at 30 fps
// when `ticksPerSecond` is 1e9 — and 0/200 at 25 fps, where the quarter-frame
// period is exactly 10 000 000 ticks. So the 1e9 chains are not decoration: the
// contract is vacuous without them, and the 25 fps chain is the control that
// proves a failure is about the quantise rather than about tiling.
//
// `MTCSchedule.hostTicksPerSecond()` is **not** in the contract — it reads
// `mach_timebase_info`, and Windows will use `QueryPerformanceFrequency`. The
// value is injected on both sides, which is exactly why the rest is pinnable.

// MARK: - Contract model (mirrored by the C# verifier's DTO)

struct MTCScheduleGoldenVector: Codable, Equatable {
    let contract: String   // "mtc-schedule"
    let version: Int       // 1
    let note: String
    let cases: [Case]

    struct Case: Codable, Equatable {
        let label: String
        let op: String     // see the header
        let rate: String   // SMPTEFramerate.rawValue
        let input: Input
        let expect: Expect
    }

    struct Input: Codable, Equatable {
        var hours: Int?
        var minutes: Int?
        var seconds: Int?
        var frames: Int?
        var anchorHostTime: UInt64?
        var ticksPerSecond: GoldenDouble?
        var sequenceIndex: Int?       // op: "sequenceTimecode"
        var quarterFrameIndex: Int?   // op: "quarterFrame"
        var from: UInt64?             // op: "batch"
        var until: UInt64?
        var boundaries: [UInt64]?     // op: "batchChain"
    }

    struct Expect: Codable, Equatable {
        // op: "cadence"
        var ticksPerQuarterFrame: GoldenDouble?
        // op: "sequenceTimecode"
        var timecode: String?
        // op: "quarterFrame"
        var byte: Int?
        var timestamp: UInt64?
        // op: "batch" — [[byte, timestamp], …]
        var messages: [[UInt64]]?
        // op: "batchChain"
        var windows: [[[UInt64]]]?
        var combined: [[UInt64]]?
    }
}

enum MTCScheduleGoldenError: Error, CustomStringConvertible {
    case notATimecode(value: [Int], rate: String)
    case boundariesNotIncreasing(label: String)

    var description: String {
        switch self {
        case let .notATimecode(value, rate):
            return "\(value) is not a valid timecode at \(rate) — fix the case matrix, not the generator"
        case let .boundariesNotIncreasing(label):
            return "\(label): a tiled chain needs strictly increasing boundaries"
        }
    }
}

// MARK: - Case matrix (the Swift implementation IS the contract source of truth)

enum MTCScheduleGolden {

    static let allRates: [SMPTEFramerate] = [.fps24, .fps25, .fps30, .fps30drop]

    /// Non-zero on purpose: a port that forgot to add the anchor still produces
    /// plausible-looking timestamps, and only a non-zero anchor catches it.
    static let anchor: UInt64 = 1000

    /// `1e9` is nanosecond ticks — the resolution at which the quantise in
    /// `quarterFrameIndex(atOrAfter:)` becomes load-bearing. `24e6` is the Apple
    /// Silicon `mach_absolute_time` rate, where every quarter-frame period is a
    /// whole number of ticks. `50` is deliberately coarse: it makes every odd
    /// quarter-frame land on a `.5` tick, which is the only way found to
    /// separate Swift's half-away-from-zero `.rounded()` from C#'s banker's
    /// `Math.Round` inside `timestamp(forQuarterFrame:)`.
    static let clocks: [Double] = [1_000_000_000, 24_000_000, 50]

    /// Valid at all four rates, and `+2` frames from here crosses a second — at
    /// 30df, sequence 5 lands on the dropped `00:01:00:02`.
    static let startTimecode = [0, 0, 59, 20]

    static let sequenceIndices = [-2, 0, 1, 5, 7, 100]

    /// 8 is the first message of sequence 1 — the first one carrying a
    /// *different* timecode, and the single most likely off-by-one in a port.
    static let quarterFrameIndices = [-1, 0, 1, 7, 8, 9, 15, 16, 200]

    /// `(rate, ticksPerSecond)` pairs for the per-message op.
    static let messageClocks: [(rate: SMPTEFramerate, ticksPerSecond: Double)] = [
        (.fps24, 1_000_000_000),
        (.fps25, 1_000_000_000),
        (.fps30, 24_000_000),
        (.fps25, 50)
    ]

    /// One tiled window chain. Boundaries are given as `(quarterFrameIndex,
    /// tickOffset)` so the intent is legible: offset `0` puts the seam exactly
    /// on an emitted timestamp, which is the case the quantise exists for.
    struct ChainCase {
        let rate: SMPTEFramerate
        let ticksPerSecond: Double
        let boundaries: [(index: Int, offset: Int64)]
        let note: String
    }

    static let chainCases: [ChainCase] = [
        ChainCase(
            rate: .fps24,
            ticksPerSecond: 1_000_000_000,
            boundaries: [(0, 0), (8, 0), (16, 0), (24, 0)],
            note: "seams-on-timestamps"
        ),
        ChainCase(
            rate: .fps30,
            ticksPerSecond: 1_000_000_000,
            boundaries: [(0, 0), (8, 0), (16, 0), (24, 0)],
            note: "seams-on-timestamps"
        ),
        // The control: at 25 fps / 1e9 the period is exactly 10 000 000 ticks,
        // so this chain is tiled correctly with or without the quantise.
        ChainCase(
            rate: .fps25,
            ticksPerSecond: 1_000_000_000,
            boundaries: [(0, 0), (8, 0), (16, 0), (24, 0)],
            note: "seams-on-timestamps-exact-period"
        ),
        ChainCase(
            rate: .fps24,
            ticksPerSecond: 24_000_000,
            boundaries: [(0, 0), (8, 0), (16, 0), (24, 0)],
            note: "seams-on-timestamps-exact-period"
        ),
        // Seams in the middle of a gap, so the ordinary `ceil` path is exercised
        // and not only the tolerance path.
        ChainCase(
            rate: .fps24,
            ticksPerSecond: 1_000_000_000,
            boundaries: [(0, 5_000_000), (5, 5_000_000), (11, 5_000_000), (17, 5_000_000)],
            note: "seams-mid-gap"
        ),
        ChainCase(
            rate: .fps30drop,
            ticksPerSecond: 1_000_000_000,
            boundaries: [(0, 0), (12, 0), (24, 0), (40, 0)],
            note: "seams-on-timestamps-dropframe"
        )
    ]

    /// Degenerate windows, expressed the same way. `count` is how many messages
    /// the window is expected to hold — recorded here only as documentation; the
    /// vector carries whatever the implementation produces.
    struct WindowCase {
        let label: String
        let from: (index: Int, offset: Int64)
        let until: (index: Int, offset: Int64)
    }

    static let windowCases: [WindowCase] = [
        WindowCase(label: "empty", from: (3, 0), until: (3, 0)),
        WindowCase(label: "inverted", from: (5, 0), until: (2, 0)),
        // `from` below the anchor clamps to quarter-frame 0 rather than going
        // negative; the second case proves the clamp still yields message 0.
        WindowCase(label: "before-anchor-empty", from: (0, -1000), until: (0, 0)),
        WindowCase(label: "before-anchor-yields-zero", from: (0, -1000), until: (0, 5_000_000)),
        // Entirely inside one gap.
        WindowCase(label: "inside-a-gap", from: (3, 1000), until: (3, 2000))
    ]

    // MARK: Helpers

    static func timecode(_ value: [Int], rate: SMPTEFramerate) throws -> Timecode {
        guard let timecode = Timecode(
            hours: value[0],
            minutes: value[1],
            seconds: value[2],
            frames: value[3],
            rate: rate
        ) else {
            throw MTCScheduleGoldenError.notATimecode(value: value, rate: rate.rawValue)
        }
        return timecode
    }

    static func schedule(_ rate: SMPTEFramerate, _ ticksPerSecond: Double) throws -> MTCSchedule {
        MTCSchedule(
            startTimecode: try timecode(startTimecode, rate: rate),
            anchorHostTime: anchor,
            ticksPerSecond: ticksPerSecond
        )
    }

    /// A boundary tick from a `(quarterFrameIndex, offset)` pair.
    static func tick(_ schedule: MTCSchedule, _ boundary: (index: Int, offset: Int64)) -> UInt64 {
        let base = schedule.timestamp(forQuarterFrame: boundary.index)
        return boundary.offset < 0
            ? base - UInt64(-boundary.offset)
            : base + UInt64(boundary.offset)
    }

    /// `[[byte, timestamp], …]` — the byte is already pinned by
    /// `golden/mtc-wire-v1.json`, so a mismatch here localises to the schedule.
    static func encode(_ messages: [MTCSchedule.Message]) -> [[UInt64]] {
        messages.map { [UInt64($0.byte), $0.timestamp] }
    }

    /// Clocks are spelled rather than formatted so a label never depends on how
    /// a platform prints a `Double`.
    static func label(_ ticksPerSecond: Double) -> String {
        switch ticksPerSecond {
        case 1_000_000_000: return "1e9"
        case 24_000_000: return "24e6"
        default: return String(Int(ticksPerSecond))
        }
    }
}
