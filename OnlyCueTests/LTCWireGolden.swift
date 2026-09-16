import Foundation
@testable import OnlyCue

// The cross-platform golden-vector contract for the **LTC wire format** (epic
// #728, M2 slice 1). macOS is the source of truth: it emits
// `golden/ltc-wire-v1.json`; the C# `OnlyCue.Core` re-implementation must
// reproduce every case exactly (verified on Windows CI).
//
// Two operations are pinned:
//
// - `frame` — the 80-bit SMPTE 12M word (`LTCFrame(timecode:)`), including the
//   rate-dependent position of the bit-polarity-correction bit (#853).
// - `encode` — the `Float` PCM for one frame (`LTCEncoder.samples`), carried as
//   run lengths rather than 2000 numbers per case.
//
// `LTCBiphaseEncoder` is deliberately **not** in the contract: it has no
// production caller. `LTCEncoder.samples` inlines its own modulation against
// *fractional* slot boundaries, which the encoder's `samplesPerHalfBit: Int`
// primitive cannot express.

// MARK: - Contract model (mirrored by the C# verifier's DTO)

struct LTCWireGoldenVector: Codable, Equatable {
    let contract: String   // "ltc-wire"
    let version: Int       // 1
    let note: String
    let cases: [Case]

    struct Case: Codable, Equatable {
        let label: String
        let op: String     // "frame" | "encode"
        let rate: String   // SMPTEFramerate.rawValue
        let input: Input
        let expect: Expect
    }

    struct Input: Codable, Equatable {
        var hours: Int
        var minutes: Int
        var seconds: Int
        var frames: Int
        var sampleRate: GoldenDouble?
        var amplitude: GoldenDouble?
        var startLevel: Bool?
    }

    struct Expect: Codable, Equatable {
        // op: "frame"
        var bits: String?            // 80 chars, transmission order, '0' / '1'
        var parityBitIndex: Int?
        var parityBit: Bool?
        var bit27: Bool?             // asserted explicitly at every rate, both
        var bit59: Bool?             // directions — that is the point of #853
        var hasEvenParity: Bool?
        var syncWordIsValid: Bool?
        // op: "encode"
        var totalSamples: Int?
        var endLevel: Bool?
        var runs: [[Int]]?           // [[+1 | -1, sampleCount], …]
    }
}

enum LTCWireGoldenError: Error, CustomStringConvertible {
    case notATimecode(value: [Int], rate: String)

    var description: String {
        switch self {
        case let .notATimecode(value, rate):
            return "\(value) is not a valid timecode at \(rate) — fix the case matrix, not the generator"
        }
    }
}

// MARK: - Generator (the Swift implementation IS the contract source of truth)

enum LTCWireGolden {

    static let allRates: [SMPTEFramerate] = [.fps24, .fps25, .fps30, .fps30drop]

    /// One `(rate, sampleRate, amplitude, startLevel)` PCM case.
    struct EncodeCase {
        let rate: SMPTEFramerate
        let sampleRate: Double
        let amplitude: Float
        /// Spelled rather than formatted, so the label never depends on how a
        /// platform prints a `Float`.
        let amplitudeLabel: String
        let startLevel: Bool
    }

    /// Timecodes per rate for `op: "frame"`.
    ///
    /// Every rate gets the zero word, an interior value, and the last frame of
    /// the day. 30df adds the two drop-frame counting boundaries. 25 fps adds a
    /// value that needs **no** correction (`01:02:03:04`) so the placement is
    /// pinned in both directions, not only where the bit happens to be set.
    static func frameInputs(for rate: SMPTEFramerate) -> [[Int]] {
        let lastFrame = rate.framesPerSecond - 1
        var values: [[Int]] = [[0, 0, 0, 0], [12, 34, 56, 7], [23, 59, 59, lastFrame]]
        if rate.isDropFrame { values += [[0, 1, 0, 2], [0, 10, 0, 0]] }
        if rate == .fps25 { values += [[1, 2, 3, 4], [17, 30, 45, 12]] }
        return values
    }

    /// The `(rate, sampleRate)` pairs are chosen by their
    /// `halfBitSamples = sampleRate / (160 · fps)` remainder — 24 fps at 48 kHz
    /// is exactly **12.5**, so every odd slot boundary is a midpoint tie. That
    /// is the case that separates Swift's half-away-from-zero `.rounded()` from
    /// C#'s banker's-rounding `Math.Round`.
    static let encodeCases: [EncodeCase] = [
        EncodeCase(rate: .fps24, sampleRate: 48000, amplitude: 0.8, amplitudeLabel: "0.8", startLevel: false),
        EncodeCase(rate: .fps25, sampleRate: 48000, amplitude: 0.8, amplitudeLabel: "0.8", startLevel: false),
        EncodeCase(rate: .fps30, sampleRate: 48000, amplitude: 0.8, amplitudeLabel: "0.8", startLevel: false),
        EncodeCase(rate: .fps30drop, sampleRate: 48000, amplitude: 0.8, amplitudeLabel: "0.8", startLevel: false),
        EncodeCase(rate: .fps24, sampleRate: 44100, amplitude: 0.8, amplitudeLabel: "0.8", startLevel: false),
        EncodeCase(rate: .fps25, sampleRate: 44100, amplitude: 0.8, amplitudeLabel: "0.8", startLevel: false),
        EncodeCase(rate: .fps30, sampleRate: 44100, amplitude: 0.8, amplitudeLabel: "0.8", startLevel: false),
        EncodeCase(rate: .fps24, sampleRate: 96000, amplitude: 0.8, amplitudeLabel: "0.8", startLevel: false),
        // The `startLevel` / `endLevel` threading `LTCFrameStream` is built on.
        EncodeCase(rate: .fps24, sampleRate: 48000, amplitude: 0.8, amplitudeLabel: "0.8", startLevel: true),
        // The product default from `LTCRoutingSettings` — proves amplitude does
        // not leak into run lengths.
        EncodeCase(rate: .fps24, sampleRate: 48000, amplitude: 0.9, amplitudeLabel: "0.9", startLevel: false)
    ]

    /// The timecode every `encode` case modulates. Valid at all four rates, and
    /// away from every drop-frame skip.
    static let encodeTimecode = [1, 2, 3, 4]

    /// Run-length encoding of `±amplitude` PCM: `[[sign, sampleCount], …]`.
    /// The full sample list would be 2000 numbers per case; the run lengths are
    /// what the rounding actually decides, so this loses nothing the contract
    /// needs while keeping the file readable.
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

    static func timecode(_ value: [Int], rate: SMPTEFramerate) throws -> Timecode {
        guard let timecode = Timecode(
            hours: value[0],
            minutes: value[1],
            seconds: value[2],
            frames: value[3],
            rate: rate
        ) else {
            throw LTCWireGoldenError.notATimecode(value: value, rate: rate.rawValue)
        }
        return timecode
    }
}
