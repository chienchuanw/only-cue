import Foundation
@testable import OnlyCue

// The cross-platform golden-vector contract for the **MTC wire format** (epic
// #728, M2 slice 1). macOS is the source of truth: it emits
// `golden/mtc-wire-v1.json`; the C# `OnlyCue.Core` re-implementation must
// reproduce every case exactly (verified on Windows CI).
//
// Four operations are pinned: the two-bit rate code, one quarter-frame data
// byte, the complete eight-message quarter-frame sequence (as whole messages,
// so the `F1` status byte is pinned too), and the Full Frame SysEx.
//
// The C# translation hazard this exists to catch: `byte << 1` and `byte >> 4`
// promote to `int` in C#, so every shift needs an explicit `(byte)` cast.
// `fullFrameBytes`' `(rateBits << 5) | (hours & 0x1F)` is the worst of them,
// and piece 7 — where the rate bits ride next to the hour's high bit — is the
// worst of the quarter frames.

// MARK: - Contract model (mirrored by the C# verifier's DTO)

struct MTCWireGoldenVector: Codable, Equatable {
    let contract: String   // "mtc-wire"
    let version: Int       // 1
    let note: String
    let cases: [Case]

    struct Case: Codable, Equatable {
        let label: String
        /// "rateBits" | "quarterFrame" | "quarterFrameSequence" | "fullFrame"
        let op: String
        let rate: String   // SMPTEFramerate.rawValue
        let input: Input
        let expect: Expect
    }

    struct Input: Codable, Equatable {
        var hours: Int?
        var minutes: Int?
        var seconds: Int?
        var frames: Int?
        /// Deliberately unclamped in the vector — `-1` and `8` are cases.
        var piece: Int?
    }

    struct Expect: Codable, Equatable {
        var byte: Int?       // "rateBits" | "quarterFrame"
        var bytes: [Int]?    // "quarterFrameSequence" | "fullFrame"
    }
}

enum MTCWireGoldenError: Error, CustomStringConvertible {
    case notATimecode(value: [Int], rate: String)

    var description: String {
        switch self {
        case let .notATimecode(value, rate):
            return "\(value) is not a valid timecode at \(rate) — fix the case matrix, not the generator"
        }
    }
}

// MARK: - Generator (the Swift implementation IS the contract source of truth)

enum MTCWireGolden {

    static let allRates: [SMPTEFramerate] = [.fps24, .fps25, .fps30, .fps30drop]

    /// The zero word, an interior value, a value whose **hour ≥ 16** (so the
    /// hour's high bit rides in piece 7 next to the rate bits), and the last
    /// frame of the day.
    static func timecodeInputs(for rate: SMPTEFramerate) -> [[Int]] {
        [[0, 0, 0, 0], [1, 2, 3, 4], [17, 30, 45, 12], [23, 59, 59, rate.framesPerSecond - 1]]
    }

    /// Out-of-range piece indices. `MTCFrame` clamps rather than trapping, which
    /// is behaviour a C# port would plausibly write as an exception instead — so
    /// it is contract, not an accident.
    static let clampedPieces = [-1, 8]

    static func timecode(_ value: [Int], rate: SMPTEFramerate) throws -> Timecode {
        guard let timecode = Timecode(
            hours: value[0],
            minutes: value[1],
            seconds: value[2],
            frames: value[3],
            rate: rate
        ) else {
            throw MTCWireGoldenError.notATimecode(value: value, rate: rate.rawValue)
        }
        return timecode
    }
}
