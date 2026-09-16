import Foundation

// The cross-platform golden-vector contract for the **LTC decoder** (epic #728,
// M3 slice 3). macOS is the source of truth: it emits `golden/ltc-decode-v1.json`;
// the C# `OnlyCue.Core` re-implementation must reproduce every case exactly
// (verified on Windows CI).
//
// Slices 1 and 2 pinned what OnlyCue *emits* — one frame's PCM
// (`ltc-wire-v1`), and how frames compose into buffers (`ltc-schedule-v1`).
// This slice pins what it *believes when it reads*, which is the harder half: a
// decoder that is subtly wrong still returns plausible timecode on a clean
// signal and only diverges at the edges.
//
// **Signals are recipes, not sample dumps.** A case names the parameters and the
// mutations; both sides build the identical `[Float]` from them (see
// `LTCDecodeGolden.samples(for:)`, whose mutation order is fixed and mirrored
// verbatim in C#). `expect.sampleCount` is carried on every case so a recipe
// that diverges fails there, loudly, instead of surfacing as a mysterious
// difference three pipeline stages downstream.
//
// **The pipeline is pinned stage by stage, not just end to end.** Five ops:
//
// - `transitions`     — `LTCDecoder.transitionIndices(in:)`: count plus the
//                       first and last 8 indices.
// - `halfBit`         — `LTCDecoder.estimateHalfBitSamples(transitions:)`, as a
//                       bit-exact `GoldenDouble`. `null` when it declines.
// - `framesPerSecond` — `LTCDecoder.framesPerSecond(sampleRate:halfBitSamples:)`.
//                       `null` when the pipeline bailed before it.
// - `bits`            — `LTCDecoder.demodulate(...)`: bit count plus the first
//                       and last 96 bits.
// - `decode`          — the headline `[(timecode, startSample)]`.
//
// With only `decode` to assert on, every hazard fails the same way and the
// mutation step cannot tell a broken comparator from a broken framer. Splitting
// them is what makes the mutants diagnostic.
//
// **Noise is deliberately absent.** Reproducing added white noise cross-platform
// needs a seeded PRNG whose output becomes part of the contract, which pins the
// PRNG rather than the decoder. The corruption here is *structural* — truncation,
// flipped bits, silence, DC — which is deterministic, expressible in the vector,
// and where ports actually break.
//
// This file is the contract *model* only — mirrored by the C# verifier's DTO in
// `windows/OnlyCue.Core.Tests/LtcDecodeVector.cs`. The signal matrix and the
// recipe builder live in `LTCDecodeGolden.swift`; the generator and the drift
// guard in `LTCDecodeGoldenVectorTests.swift`.

// MARK: - Contract model

struct LTCDecodeGoldenVector: Codable, Equatable {
    let contract: String   // "ltc-decode"
    let version: Int       // 1
    let note: String
    let cases: [Case]

    struct Case: Codable, Equatable {
        let label: String
        let op: String     // see the header
        let input: Input
        let expect: Expect
    }

    /// The recipe for one signal. Every field is applied in the order documented
    /// on `LTCDecodeGolden.samples(for:)`; a port that reorders them builds a
    /// different buffer and fails on `sampleCount`.
    struct Input: Codable, Equatable {
        let rate: String          // SMPTEFramerate.rawValue
        let sampleRate: GoldenDouble
        let amplitude: GoldenDouble
        let timecode: [Int]       // [hours, minutes, seconds, frames]
        let frameCount: Int
        var leadSilenceSamples = 0
        var trailSilenceSamples = 0
        var truncateToSamples: Int?
        var flips: [FrameFlip]?      // bit flips, per encoded frame
        var offsetBy: GoldenDouble?  // DC added to every sample, last
    }

    /// A bit-flip mutation on one encoded frame. A list, not a single frame,
    /// because the `spurious-sync-after-a-broken-frame` case needs two: one frame
    /// broken and the *next* one carrying the trap.
    struct FrameFlip: Codable, Equatable {
        let frame: Int       // 0-based index into the encoded frames
        let indices: [Int]   // 0-based bit positions, transmission order
    }

    struct Frame: Codable, Equatable {
        let timecode: String
        let startSample: Int
    }

    struct Expect: Codable, Equatable {
        /// Carried by every op — the recipe's own fingerprint.
        let sampleCount: Int
        // op: "decode"
        var frames: [Frame]?
        // op: "transitions"
        var transitionCount: Int?
        var firstTransitions: [Int]?
        var lastTransitions: [Int]?
        // op: "halfBit"
        var halfBitSamples: GoldenDouble?
        // op: "framesPerSecond"
        var framesPerSecond: Int?
        // op: "bits"
        var bitCount: Int?
        var firstBits: String?
        var lastBits: String?
    }
}

enum LTCDecodeGoldenError: Error, CustomStringConvertible {
    case notATimecode(value: [Int], rate: String)

    var description: String {
        switch self {
        case let .notATimecode(value, rate):
            return "\(value) is not a valid timecode at \(rate) — fix the case matrix, not the generator"
        }
    }
}
