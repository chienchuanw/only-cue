import Foundation
@testable import OnlyCue

// The signal matrix and the recipe builder behind `golden/ltc-decode-v1.json`.
// The contract model it fills in is `LTCDecodeGoldenVector.swift`; the generator
// and the drift guard are `LTCDecodeGoldenVectorTests.swift`.

// MARK: - Signals

enum LTCDecodeGolden {

    /// Every op is emitted for every signal, so a failure localises to a stage
    /// rather than to a case.
    static let ops = ["transitions", "halfBit", "framesPerSecond", "bits", "decode"]

    /// How many leading / trailing values of the long lists are pinned. 8
    /// transitions span more than three bits at every rate in the matrix, and 96
    /// bits is more than one 80-bit frame — enough that a one-bit shift moves
    /// the window, short enough that the file stays readable.
    static let edgeTransitions = 8
    static let edgeBits = 96

    /// One signal recipe. Defaults are the clean case; every structural case is
    /// this with one field set, so the diff between a case and its control is
    /// exactly the corruption under test.
    struct Signal {
        let label: String
        let rate: SMPTEFramerate
        let sampleRate: Double
        let start: [Int]
        let frameCount: Int
        var amplitude: Float = LTCEncoder.defaultAmplitude
        var leadSilenceSamples = 0
        var trailSilenceSamples = 0
        var truncateToSamples: Int?
        var flipBitInFrame: Int?
        var flipBitIndices: [Int]?
        var offsetBy: Float?
    }

    static let allRates: [SMPTEFramerate] = [.fps24, .fps25, .fps30, .fps30drop]
    static let sampleRates: [Double] = [48000, 44100]

    /// Positioned so the run crosses the second boundary *inside* the frames the
    /// decoder actually recovers (it drops the leading and trailing one) — and at
    /// 30df crosses the minute boundary whose first two frame numbers the counting
    /// rule skips.
    static func boundaryStart(_ rate: SMPTEFramerate) -> [Int] {
        [0, 0, 59, rate.framesPerSecond - 3]
    }

    /// 24 fps at 48 kHz: 160 half-bit slots of 12.5 samples each → 2000 samples
    /// per frame, and slot boundaries that alternate 13 / 12. The reference
    /// geometry for every structural case below.
    static let referenceRate = SMPTEFramerate.fps24
    static let referenceSampleRate: Double = 48000
    static let referenceSamplesPerFrame = 2000
    static let referenceStart = [1, 0, 0, 0]

    /// **Six, because the decoder always loses the leading and the trailing
    /// frame.** The comparator does not record its first latch, so the opening
    /// bit boundary is missing and frame 0's 80-bit window never completes; the
    /// final bit has no closing transition, so the last frame's sync word is one
    /// bit short. `LTCDecoderTests.assertRoundTrips` has documented that since the
    /// decoder shipped. A 4-frame run therefore decodes exactly 2, which leaves
    /// `parity-flipped-middle-frame` with no "frames after it" to check — the
    /// whole point of the case. Six decodes four, so the corrupted frame has
    /// neighbours on both sides.
    static let referenceFrameCount = 6

    static func reference(
        _ label: String,
        frameCount: Int = referenceFrameCount,
        mutate: (inout Signal) -> Void = { _ in }
    ) -> Signal {
        var signal = Signal(
            label: label,
            rate: referenceRate,
            sampleRate: referenceSampleRate,
            start: referenceStart,
            frameCount: frameCount
        )
        mutate(&signal)
        return signal
    }

    // MARK: Clean round-trip — the positive core

    static var cleanSignals: [Signal] {
        let matrix = allRates.flatMap { rate in
            sampleRates.flatMap { sampleRate -> [Signal] in
                [
                    Signal(
                        label: "clean",
                        rate: rate,
                        sampleRate: sampleRate,
                        start: referenceStart,
                        frameCount: referenceFrameCount
                    ),
                    Signal(
                        label: "boundary",
                        rate: rate,
                        sampleRate: sampleRate,
                        start: boundaryStart(rate),
                        frameCount: referenceFrameCount
                    )
                ]
            }
        }
        return matrix + [
            // A full second. Four frames hide drift that accumulates; thirty
            // do not.
            Signal(label: "long", rate: .fps30, sampleRate: 48000, start: [1, 0, 0, 0], frameCount: 30),
            // The comparator threshold is a fraction of the measured RMS, not an
            // absolute level — so a quiet signal must decode identically.
            reference("quiet") { $0.amplitude = 0.25 }
        ]
    }

    // MARK: Structural corruption — the negative core

    /// Bit 3 is the high bit of the frames-units BCD digit: flipping it changes
    /// the payload *and* makes the parity odd, so the word is syntactically a
    /// frame (its sync word is intact) but fails `isWellFormed`.
    ///
    /// This is the case hazard 8 exists for. `extractFrames` advances 80 bits on
    /// a **sync match**, not on a **valid frame** — so the corrupted frame is
    /// consumed and the search resumes cleanly after it. A port that puts the
    /// advance inside the validity check keeps sliding bit-by-bit through the bad
    /// frame and can re-lock on a spurious window. The expectation that catches
    /// that is not "one frame is missing" but "*only* that frame is missing, and
    /// every other frame is still at its byte-identical `startSample`".
    static let parityFlipBit = 3

    /// Two sync-word bits, both `1`, so parity stays **even** and only the sync
    /// word is broken. One flip would break both gates at once and the case
    /// could not tell them apart.
    static let syncFlipBits = [70, 71]

    /// Frames driven out of range. Bit 0 is the frames-units LSB and bits 8 / 9
    /// are the two frames-tens bits; bit 27 is the 24 fps parity position, which
    /// carries no data and is flipped only to make the flip count even so parity
    /// survives. Applied to `flipInFrame` — `01:00:00:02`, frames = 2 — that reads
    /// back as **33**, which no rate has. So the word *is* well-formed and
    /// `timecode(framesPerSecond:)` still returns `nil` — validity and range are
    /// two separate gates, and a port that folds them into one passes the clean
    /// cases and fails here.
    static let bcdOutOfRangeBits = [0, 8, 9, 27]

    /// Which frame of the run every corruption lands on. The decoder drops the
    /// leading and trailing frame, so the recoverable run of a
    /// `referenceFrameCount` signal is frames 1…4; putting the corruption on
    /// frame 2 leaves recovered neighbours on both sides of it.
    static let flipInFrame = 2

    static var structuralSignals: [Signal] {
        [
            reference("parity-flipped-middle-frame") {
                $0.flipBitInFrame = flipInFrame
                $0.flipBitIndices = [parityFlipBit]
            },
            reference("sync-word-broken") {
                $0.flipBitInFrame = flipInFrame
                $0.flipBitIndices = syncFlipBits
            },
            reference("bcd-out-of-range") {
                $0.flipBitInFrame = flipInFrame
                $0.flipBitIndices = bcdOutOfRangeBits
            },
            // Cut 4.5 frames in: the last window is incomplete and must simply
            // not produce a frame, while the frames before it still decode.
            reference("truncated-mid-frame") {
                $0.truncateToSamples = referenceSamplesPerFrame * 9 / 2
            },
            // Cut exactly on a frame boundary. The final bit of the sync word is
            // a `1`, and a `1` needs a *following* transition to be emitted —
            // hazard 7. A port that drops `demodulate`'s `index + 1 <
            // transitions.count` guard emits one extra bit here, which shifts the
            // last 80-bit window.
            reference("truncated-immediately-after-a-frame") {
                $0.truncateToSamples = referenceSamplesPerFrame * 4
            },
            // Fewer than three transitions: the `guard transitions.count >= 3`
            // early return, reached with a real signal rather than with silence.
            reference("too-few-transitions") { $0.truncateToSamples = 30 },
            Signal(
                label: "silence-only",
                rate: referenceRate,
                sampleRate: referenceSampleRate,
                start: referenceStart,
                frameCount: 0,
                leadSilenceSamples: 4000
            ),
            // Hazard 4. Half a second of digital silence in front of the LTC.
            // The reference RMS is global, so it still clears the floor and the
            // frames still decode — at a `startSample` offset by the lead. A port
            // that windows the RMS gives the silent blocks a threshold of their
            // own and re-introduces #793.
            reference("silence-lead-in") { $0.leadSilenceSamples = 24000 }
        ] + dcOffsetLadder + silenceFloorLadder
    }

    /// The comparator is symmetric about zero and there is no DC blocker, so a
    /// DC offset `D` on a `±A` square wave moves the samples to `D ± A` while the
    /// reference RMS becomes `√(D² + A²)`. The negative latch stops firing — and
    /// the decode collapses to nothing — once
    ///
    ///     A − D < 0.3·√(D² + A²)
    ///
    /// which at `A = 0.8` solves to `D ≈ 0.51462`. The three rungs sit either
    /// side of that root: **0.5 still decodes** (and must decode *identically* to
    /// the clean signal, since the latch indices are unchanged), **0.55 decodes
    /// nothing**, and **0.5146** is within about 1e-5 of the root — the closest
    /// this contract gets to a sample sitting on the threshold, which is where a
    /// port that computes the threshold in `double` instead of `Float` could
    /// diverge.
    ///
    /// Pinning the collapse rather than assuming it is the point: a port that
    /// "helpfully" adds a DC blocker decodes all three and fails the last two.
    static let dcOffsets: [Float] = [0.5, 0.5146, 0.55]

    static var dcOffsetLadder: [Signal] {
        dcOffsets.map { offset in
            reference("dc-offset/d\(offset)") { $0.offsetBy = offset }
        }
    }

    /// `silenceRMSFloor` is 1e-4 and the signal is a square wave at `±amplitude`,
    /// so its RMS *is* the amplitude (up to the accumulation order `rms` uses —
    /// which is itself hazard 1). Four rungs straddling the floor pin its
    /// **position**, not merely its existence: a port whose floor is an order out,
    /// or which compares `>` instead of `>=`, cannot pass all four.
    static let silenceFloorAmplitudes: [Float] = [2e-4, 1e-4, 9.9e-5, 5e-5]

    static var silenceFloorLadder: [Signal] {
        silenceFloorAmplitudes.map { amplitude in
            reference("silence-floor/a\(amplitude)") { $0.amplitude = amplitude }
        }
    }

    static var allSignals: [Signal] { cleanSignals + structuralSignals }

    // MARK: - The recipe builder (mirrored verbatim in C#)

    static func timecode(_ value: [Int], rate: SMPTEFramerate) throws -> Timecode {
        guard let timecode = Timecode(
            hours: value[0],
            minutes: value[1],
            seconds: value[2],
            frames: value[3],
            rate: rate
        ) else {
            throw LTCDecodeGoldenError.notATimecode(value: value, rate: rate.rawValue)
        }
        return timecode
    }

    /// Build the signal a case describes. **The order is the contract:**
    ///
    /// 1. Encode `frameCount` consecutive frames from `start`, biphase polarity
    ///    threaded across the joins exactly as `LTCFrameStream` does. The frame
    ///    at `flipBitInFrame` is re-encoded from its word with `flipBitIndices`
    ///    toggled — so corruption is a genuinely wrong word on the wire, and the
    ///    polarity thread carries its consequences into the frames that follow,
    ///    just as a real encoder would have.
    /// 2. Prepend `leadSilenceSamples` zeros, append `trailSilenceSamples` zeros.
    /// 3. Truncate to `truncateToSamples` (a prefix).
    /// 4. Add `offsetBy` to every sample.
    ///
    /// Silence is digital zero, not `±0` of some small amplitude, so the RMS
    /// arithmetic is unambiguous.
    static func samples(for signal: Signal) throws -> [Float] {
        var output = [Float](repeating: 0, count: signal.leadSilenceSamples)
        output += try body(of: signal)
        output += [Float](repeating: 0, count: signal.trailSilenceSamples)
        if let limit = signal.truncateToSamples {
            output = Array(output.prefix(max(0, limit)))
        }
        if let offset = signal.offsetBy {
            output = output.map { $0 + offset }
        }
        return output
    }

    private static func body(of signal: Signal) throws -> [Float] {
        guard signal.frameCount > 0 else { return [] }
        let start = try timecode(signal.start, rate: signal.rate)
        var output: [Float] = []
        var level = false
        for offset in 0..<signal.frameCount {
            let (frameSamples, endLevel) = LTCEncoder.samples(
                for: frame(of: signal, at: offset, from: start),
                framesPerSecond: signal.rate.framesPerSecond,
                sampleRate: signal.sampleRate,
                amplitude: signal.amplitude,
                startLevel: level
            )
            output += frameSamples
            level = endLevel
        }
        return output
    }

    private static func frame(of signal: Signal, at offset: Int, from start: Timecode) -> LTCFrame {
        let frame = LTCFrame(timecode: Timecode(frameCount: start.frameCount + offset, rate: signal.rate))
        guard signal.flipBitInFrame == offset, let indices = signal.flipBitIndices else { return frame }
        var bits = frame.bits
        for index in indices { bits[index].toggle() }
        return LTCFrame(bits: bits)
    }

    // MARK: - Pipeline taps

    /// The decoder's stages, run in `decode`'s own order and with `decode`'s own
    /// guards, so a `null` in the vector means "the pipeline stopped here"
    /// rather than "the generator chose not to ask".
    struct Pipeline {
        let transitions: [Int]
        let halfBitSamples: Double?
        let framesPerSecond: Int?
        let bits: [Bool]?
    }

    static func pipeline(of samples: [Float], sampleRate: Double) -> Pipeline {
        let transitions = LTCDecoder.transitionIndices(in: samples)
        guard transitions.count >= 3,
              let halfBit = LTCDecoder.estimateHalfBitSamples(transitions: transitions) else {
            return Pipeline(transitions: transitions, halfBitSamples: nil, framesPerSecond: nil, bits: nil)
        }
        return Pipeline(
            transitions: transitions,
            halfBitSamples: halfBit,
            framesPerSecond: LTCDecoder.framesPerSecond(sampleRate: sampleRate, halfBitSamples: halfBit),
            bits: LTCDecoder.demodulate(transitions: transitions, halfBitSamples: halfBit).bits
        )
    }

    static func bitString(_ bits: [Bool]) -> String {
        String(bits.map { $0 ? "1" : "0" })
    }
}
