import Foundation
@testable import OnlyCue

// The cross-platform golden-vector contract for the **LTC scheduling layer**
// (epic #728, M3 slice 2). macOS is the source of truth: it emits
// `golden/ltc-schedule-v1.json`; the C# `OnlyCue.Core` re-implementation must
// reproduce every case exactly (verified on Windows CI).
//
// Slice 1 (`golden/ltc-wire-v1.json`) pinned what *one* frame looks like. This
// contract pins the layer above — how frames compose into a stream and how that
// stream is cut into playback buffers:
//
// - `stream`            — `LTCFrameStream.samplesPerFrame` and the PCM across
//                         frame joins.
// - `streamTimecode`    — `LTCFrameStream.timecode(atFrameOffset:)`.
// - `schedule`          — `LTCSchedule.samplesPerBuffer` / `bufferDuration`.
// - `buffer`            — `LTCSchedule.timecode(forBufferIndex:)` and the
//                         buffer's sample count.
// - `bufferSeam`        — the PCM across a *buffer* join, where polarity is
//                         deliberately not threaded.
// - `targetBufferCount` — the refill arithmetic.
// - `framesPerBuffer`   — the static buffer-size helper.
//
// **PCM is pinned by structure plus seam windows, not exhaustively.** Slice 1
// already pins every sample of a single frame, so the new information here is
// composition. Actual samples appear only as run lengths in a ±`joinWindow`
// sample window around each join — wide enough to straddle the boundary and show
// an inverted join, narrow enough that an 8-frame stream costs a few dozen pairs
// instead of 16 000 floats.
//
// What those windows do **not** catch, stated plainly so nobody assumes
// otherwise: dropping `LTCFrameStream`'s polarity threading entirely. Every LTC
// frame ends at the level it started at (parity forces an even flip count), so
// threading and resetting emit identical PCM. That is an equivalent mutant, and
// `test_joinWindow_catchesAnInvertedJoin_butResettingOneIsEquivalent` proves it
// rather than leaving it as a comfortable assumption.

// MARK: - Contract model (mirrored by the C# verifier's DTO)

struct LTCScheduleGoldenVector: Codable, Equatable {
    let contract: String   // "ltc-schedule"
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

    /// Run lengths around one join, and the sample index the join sits at.
    struct Join: Codable, Equatable {
        let at: Int
        let runs: [[Int]]  // [[+1 | -1, sampleCount], …]
    }

    struct Input: Codable, Equatable {
        var hours: Int?
        var minutes: Int?
        var seconds: Int?
        var frames: Int?
        var sampleRate: GoldenDouble?
        var amplitude: GoldenDouble?
        var frameCount: Int?              // op: "stream"
        var frameOffset: Int?             // op: "streamTimecode"
        var framesPerBuffer: Int?         // op: "schedule" | "buffer" | "bufferSeam" | "targetBufferCount"
        var bufferIndex: Int?             // op: "buffer" | "bufferSeam"
        var elapsedSeconds: GoldenDouble? // op: "targetBufferCount"
        var leadBuffers: Int?
        var targetSeconds: GoldenDouble?  // op: "framesPerBuffer"
    }

    struct Expect: Codable, Equatable {
        // op: "stream"
        var samplesPerFrame: Int?
        var totalSamples: Int?
        var firstSampleIsHigh: Bool?
        var lastSampleIsHigh: Bool?
        var joins: [Join]?
        // op: "streamTimecode" | "buffer"
        var timecode: String?
        // op: "schedule"
        var samplesPerBuffer: Int?
        var bufferDuration: GoldenDouble?
        // op: "buffer"
        var sampleCount: Int?
        // op: "bufferSeam"
        var previousEndsHigh: Bool?
        var nextStartsHigh: Bool?
        var runs: [[Int]]?
        // op: "targetBufferCount"
        var count: Int?
        // op: "framesPerBuffer"
        var frames: Int?
    }
}

enum LTCScheduleGoldenError: Error, CustomStringConvertible {
    case notATimecode(value: [Int], rate: String)

    var description: String {
        switch self {
        case let .notATimecode(value, rate):
            return "\(value) is not a valid timecode at \(rate) — fix the case matrix, not the generator"
        }
    }
}

// MARK: - Case matrix (the Swift implementation IS the contract source of truth)

enum LTCScheduleGolden {

    static let allRates: [SMPTEFramerate] = [.fps24, .fps25, .fps30, .fps30drop]

    /// Every case modulates at the slice-1 amplitude, so a run-length mismatch
    /// is never about amplitude — that is already pinned by `ltc-wire-v1`.
    static let amplitude: Float = 0.8

    /// Half-width, in samples, of the PCM window kept around each join. At
    /// 48 kHz / 24 fps a half-bit is 12.5 samples, so 16 spans more than a full
    /// bit either side: enough to see the straddling run *and* its neighbours.
    static let joinWindow = 16

    // MARK: Stream

    struct StreamCase {
        let rate: SMPTEFramerate
        let sampleRate: Double
        let frameCount: Int
    }

    /// `(rate, sampleRate)` pairs are reused from slice 1's encode matrix, so the
    /// per-frame PCM underneath each case is already independently pinned and a
    /// failure here localises to composition.
    ///
    /// `frameCount` 1 proves `joins` is empty; 2 is the minimal join; 8 proves
    /// the join is right at *every* boundary rather than only once. 0 and -3
    /// pin the `guard count > 0` early return.
    static let streamCases: [StreamCase] = [
        StreamCase(rate: .fps24, sampleRate: 48000, frameCount: 1),
        StreamCase(rate: .fps24, sampleRate: 48000, frameCount: 2),
        StreamCase(rate: .fps24, sampleRate: 48000, frameCount: 8),
        StreamCase(rate: .fps25, sampleRate: 48000, frameCount: 2),
        StreamCase(rate: .fps30, sampleRate: 48000, frameCount: 2),
        StreamCase(rate: .fps30drop, sampleRate: 48000, frameCount: 2),
        // 44100 / 24 is 1837.5 — `samplesPerFrame` rounds, so the joins land at
        // 1838-sample multiples rather than at an exact frame period.
        StreamCase(rate: .fps24, sampleRate: 44100, frameCount: 8),
        StreamCase(rate: .fps25, sampleRate: 44100, frameCount: 2),
        StreamCase(rate: .fps30, sampleRate: 44100, frameCount: 2),
        StreamCase(rate: .fps24, sampleRate: 96000, frameCount: 2),
        StreamCase(rate: .fps24, sampleRate: 48000, frameCount: 0),
        StreamCase(rate: .fps24, sampleRate: 48000, frameCount: -3)
    ]

    /// Valid at all four rates and clear of every drop-frame skip.
    static let streamTimecode = [1, 2, 3, 4]

    /// Offsets for `streamTimecode`, from `00:00:59:00` so they cross a second
    /// boundary and, at 30df, the dropped-frame minute boundary.
    static let frameOffsets = [-5, -1, 0, 1, 23, 24, 25, 30, 31]
    static let frameOffsetOrigin = [0, 0, 59, 0]

    // MARK: Schedule

    struct ScheduleCase {
        let rate: SMPTEFramerate
        let sampleRate: Double
        let framesPerBuffer: Int
        let start: [Int]
    }

    /// 24 fps at 44 100 Hz is the load-bearing case: `samplesPerBuffer` rounds
    /// **per frame and then multiplies**, so it is `4 × round(1837.5) = 7352`.
    /// A port that wrote `round(4 × 44100 / 24)` gets 7350 — two samples short
    /// per buffer, forever. At 48 kHz the division is exact and the hazard is
    /// invisible.
    static let scheduleCases: [ScheduleCase] = [
        ScheduleCase(rate: .fps24, sampleRate: 44100, framesPerBuffer: 4, start: [1, 0, 0, 0]),
        ScheduleCase(rate: .fps24, sampleRate: 48000, framesPerBuffer: 1, start: [1, 0, 0, 0]),
        ScheduleCase(rate: .fps24, sampleRate: 48000, framesPerBuffer: 2, start: [1, 0, 0, 0]),
        ScheduleCase(rate: .fps24, sampleRate: 48000, framesPerBuffer: 4, start: [1, 0, 0, 0]),
        ScheduleCase(rate: .fps24, sampleRate: 48000, framesPerBuffer: 25, start: [1, 0, 0, 0]),
        ScheduleCase(rate: .fps25, sampleRate: 48000, framesPerBuffer: 4, start: [1, 0, 0, 0]),
        ScheduleCase(rate: .fps30, sampleRate: 48000, framesPerBuffer: 4, start: [1, 0, 0, 0]),
        ScheduleCase(rate: .fps30drop, sampleRate: 48000, framesPerBuffer: 4, start: [1, 0, 0, 0]),
        ScheduleCase(rate: .fps25, sampleRate: 44100, framesPerBuffer: 4, start: [1, 0, 0, 0]),
        ScheduleCase(rate: .fps30, sampleRate: 44100, framesPerBuffer: 4, start: [1, 0, 0, 0]),
        // Buffer 6 starts 30 frames after 00:00:59:00, i.e. on the dropped
        // 00:01:00:02 — proves the buffer timecode goes through
        // `Timecode(frameCount:)` and not naive field arithmetic.
        ScheduleCase(rate: .fps30drop, sampleRate: 48000, framesPerBuffer: 5, start: [0, 0, 59, 0])
    ]

    struct BufferCase {
        let schedule: ScheduleCase
        let index: Int
    }

    /// Negative indices pin the `max(0, index)` clamp, which a port would
    /// plausibly write as a precondition or as a negative array index.
    static var bufferCases: [BufferCase] {
        let plain = scheduleCases.filter { $0.sampleRate == 48000 && $0.framesPerBuffer == 2 }
            + scheduleCases.filter { $0.sampleRate == 44100 && $0.framesPerBuffer == 4 && $0.rate == .fps24 }
        let dropFrame = scheduleCases.filter { $0.framesPerBuffer == 5 }
        return plain.flatMap { schedule in [-2, 0, 1, 3].map { BufferCase(schedule: schedule, index: $0) } }
            + dropFrame.flatMap { schedule in [0, 5, 6].map { BufferCase(schedule: schedule, index: $0) } }
    }

    /// Buffer joins are where polarity is *not* threaded, so this is the only op
    /// that can catch a port whose buffers do not abut cleanly.
    static var bufferSeamCases: [BufferCase] {
        let base = scheduleCases.filter {
            ($0.sampleRate == 48000 && $0.framesPerBuffer == 2 && $0.rate == .fps24)
                || ($0.sampleRate == 44100 && $0.framesPerBuffer == 4 && $0.rate == .fps24)
        }
        return base.flatMap { schedule in [0, 1, 3].map { BufferCase(schedule: schedule, index: $0) } }
    }

    // MARK: Refill arithmetic

    struct TargetCountCase {
        let schedule: ScheduleCase
        let elapsedSeconds: Double
        let leadBuffers: Int
    }

    /// `bufferDuration` for the 25 fps / 4-frame schedule is 0.16 s.
    /// `0.032` is `0.2 × bufferDuration`: `ceil` gives 1 and `round` gives 0,
    /// which is the difference between staying ahead of the playhead and
    /// starving it. The negatives pin both `max(0, …)` clamps.
    static let elapsedValues: [Double] = [-1, 0, 0.001, 0.032, 0.16, 0.479, 0.48, 0.481]
    static let leadValues = [-1, 0, 2]

    static var targetCountCases: [TargetCountCase] {
        guard let schedule = scheduleCases.first(where: { $0.rate == .fps25 && $0.framesPerBuffer == 4 }),
              let single = scheduleCases.first(where: { $0.rate == .fps24 && $0.framesPerBuffer == 1 })
        else { return [] }
        return elapsedValues.flatMap { elapsed in
            leadValues.map { TargetCountCase(schedule: schedule, elapsedSeconds: elapsed, leadBuffers: $0) }
        } + [TargetCountCase(schedule: single, elapsedSeconds: 0.5, leadBuffers: 1)]
    }

    /// `0.1 s` and `0.5 s` at 25 fps are 2.5 and 12.5 — Swift's
    /// half-away-from-zero `.rounded()` gives 3 and 13 where C#'s banker's
    /// `Math.Round` gives 2 and 12. `0.3 s` at 25 fps is 7.5, where the two
    /// modes **agree**: it is the control that proves a failure is about the tie
    /// and not about ties in general. `-1` and `0.02` pin the `max(1, …)` floor.
    static let targetSecondsValues: [Double] = [-1, 0, 0.02, 0.1, 0.3, 0.5, 1.0]

    // MARK: Helpers

    /// Run-length encoding of `±amplitude` PCM: `[[sign, sampleCount], …]`.
    /// Identical to slice 1's, so both contracts read the same way.
    static func runs(of samples: [Float]) -> [[Int]] {
        var encoded: [[Int]] = []
        for sample in samples {
            let sign = sample < 0 ? -1 : 1
            if encoded.last?.first == sign {
                encoded[encoded.count - 1][1] += 1
            } else {
                encoded.append([sign, 1])
            }
        }
        return encoded
    }

    /// The `±joinWindow` slice of `samples` centred on `index`, clipped to the
    /// array. Clipping matters only for pathologically short frames; the matrix
    /// has none, and a clipped window would still be diagnostic.
    static func window(of samples: [Float], around index: Int) -> [Float] {
        let lower = max(0, index - joinWindow)
        let upper = min(samples.count, index + joinWindow)
        guard lower < upper else { return [] }
        return Array(samples[lower..<upper])
    }

    static func timecode(_ value: [Int], rate: SMPTEFramerate) throws -> Timecode {
        guard let timecode = Timecode(
            hours: value[0],
            minutes: value[1],
            seconds: value[2],
            frames: value[3],
            rate: rate
        ) else {
            throw LTCScheduleGoldenError.notATimecode(value: value, rate: rate.rawValue)
        }
        return timecode
    }

    static func stream(_ rate: SMPTEFramerate, _ sampleRate: Double, start: [Int]) throws -> LTCFrameStream {
        LTCFrameStream(
            startTimecode: try timecode(start, rate: rate),
            sampleRate: sampleRate,
            amplitude: amplitude
        )
    }

    static func schedule(_ spec: ScheduleCase) throws -> LTCSchedule {
        LTCSchedule(
            startTimecode: try timecode(spec.start, rate: spec.rate),
            sampleRate: spec.sampleRate,
            framesPerBuffer: spec.framesPerBuffer,
            amplitude: amplitude
        )
    }
}
