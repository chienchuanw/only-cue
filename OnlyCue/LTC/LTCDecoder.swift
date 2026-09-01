import Foundation

/// Recovers SMPTE timecode from a stream of LTC audio samples — the inverse of
/// `LTCEncoder` / `LTCFrameStream`. Pure: feed it mono `Float` samples + the
/// sample rate, get back the timecodes it found and where (in samples) each
/// frame began.
///
/// Pipeline: zero-crossing detection → biphase-mark demodulation (a bit boundary
/// at every transition; a `1` adds a mid-bit transition, so a `0` spans one bit
/// period and a `1` spans two half-bit intervals) → sliding 80-bit window → lock
/// when the trailing 16 bits are the sync word `0011 1111 1111 1101` → validate
/// (sync + even parity + in-range BCD fields) → `Timecode`. The bit period is
/// estimated from the transition-interval histogram, so the framerate (24 / 25 /
/// 30, ×drop-frame from bit 10) is recovered, not assumed.
///
/// v1 is tuned for clean signals (a file striped by software, or our own
/// generator played back) — it does not do PLL-style jitter tracking, half-speed
/// / reverse playback, or 25 fps's bit-59 parity variant.
enum LTCDecoder {

    /// One recovered frame: the timecode and the sample index where its first
    /// bit started.
    struct DecodedFrame: Equatable, Sendable {
        let timecode: Timecode
        let startSample: Int
    }

    /// Decode every well-formed LTC frame in `samples`. Empty if the signal is
    /// too short / noisy to lock.
    static func decode(samples: [Float], sampleRate: Double) -> [DecodedFrame] {
        precondition(sampleRate > 0, "sample rate must be positive")
        let transitions = transitionIndices(in: samples)
        guard transitions.count >= 3 else { return [] }
        guard let halfBit = estimateHalfBitSamples(transitions: transitions) else { return [] }

        let bitRate = sampleRate / (2.0 * halfBit)
        let framesPerSecond = Int((bitRate / 80.0).rounded())

        let stream = demodulate(transitions: transitions, halfBitSamples: halfBit)
        return extractFrames(stream: stream, framesPerSecond: framesPerSecond)
    }

    // MARK: - Zero crossings

    /// A buffer whose RMS falls below this carries no signal worth decoding.
    /// Four times above the dither peak measured in a real Logic Pro mp3
    /// export (2.35e-5) and three and a half orders of magnitude below that
    /// file's LTC (RMS 0.33). Rejecting such a buffer outright is what stops
    /// an all-silent channel from having its own noise amplified into a
    /// threshold. See #793.
    static let silenceRMSFloor: Float = 1e-4

    /// Fraction of the reference amplitude at which the comparator latches.
    /// Verified correct across a 20x span (0.02...0.40) against a real file:
    /// the LTC channel decoded 226-227 frames at every setting and the music
    /// channel decoded none.
    private static let thresholdFraction: Float = 0.3

    private static func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var total = 0.0
        for sample in samples { total += Double(sample) * Double(sample) }
        return Float((total / Double(samples.count)).squareRoot())
    }

    /// Indices where the signal crosses a hysteresis comparator.
    ///
    /// A bare zero-crossing detector has no noise immunity: the dither in a
    /// decoded mp3's silent lead-in flips sign every sample or two, which
    /// swamps the interval statistics the demodulator depends on. Latching
    /// only past +/- `thresholdFraction * rms` gates that out.
    ///
    /// The reference amplitude is deliberately computed over the WHOLE
    /// buffer and must stay global. A per-block adaptive reference
    /// re-introduces the bug: a block of pure noise has an RMS equal to the
    /// noise, so its threshold collapses to the noise floor.
    private static func transitionIndices(in samples: [Float]) -> [Int] {
        let reference = rms(samples)
        guard reference >= silenceRMSFloor else { return [] }
        let threshold = thresholdFraction * reference

        var indices: [Int] = []
        var state = 0
        for (index, sample) in samples.enumerated() {
            if state <= 0, sample > threshold {
                if state != 0 { indices.append(index) }
                state = 1
            } else if state >= 0, sample < -threshold {
                if state != 0 { indices.append(index) }
                state = -1
            }
        }
        return indices
    }

    // MARK: - Bit-period estimate

    /// Estimates the half-bit period from the shortest transition intervals.
    /// Biphase-mark encoding emits one transition per `0` bit and two per `1`,
    /// so the shortest intervals are the half-bit period; the estimate is the
    /// mean of every interval within 1.5x of the minimum. This is only sound
    /// because `transitionIndices` gates out noise first — an ungated minimum
    /// collapses to 1 sample (#793).
    private static func estimateHalfBitSamples(transitions: [Int]) -> Double? {
        var intervals: [Int] = []
        intervals.reserveCapacity(transitions.count - 1)
        for index in 1..<transitions.count {
            intervals.append(transitions[index] - transitions[index - 1])
        }
        guard let smallest = intervals.min(), smallest > 0 else { return nil }
        let lowerCluster = intervals.filter { Double($0) < 1.5 * Double(smallest) }
        guard !lowerCluster.isEmpty else { return nil }
        return Double(lowerCluster.reduce(0, +)) / Double(lowerCluster.count)
    }

    // MARK: - Biphase-mark demodulation

    /// The recovered bit sequence plus, for each bit, the sample index of the
    /// transition that began it (so a frame's start can be reported in samples).
    private struct BitStream {
        var bits: [Bool] = []
        var startSamples: [Int] = []
    }

    /// Walk the transitions, classifying each inter-transition interval as a
    /// whole bit period (`0`) or a half (the first of the two halves of a `1`).
    /// Intervals that fit neither are dropped (re-sync).
    private static func demodulate(transitions: [Int], halfBitSamples: Double) -> BitStream {
        var stream = BitStream()
        var index = 1
        while index < transitions.count {
            let start = transitions[index - 1]
            let halfBits = Double(transitions[index] - start) / halfBitSamples
            if halfBits >= 1.5, halfBits < 2.5 {
                stream.bits.append(false)
                stream.startSamples.append(start)
                index += 1
            } else if halfBits >= 0.5, halfBits < 1.5, index + 1 < transitions.count {
                // A `1` is two ~half-bit intervals; consume both.
                stream.bits.append(true)
                stream.startSamples.append(start)
                index += 2
            } else {
                index += 1
            }
        }
        return stream
    }

    // MARK: - Frame framing

    /// Slide an 80-bit window over the bit stream; when the trailing 16 bits are
    /// the sync word, the window is a complete frame (payload bits 0–63, sync
    /// 64–79). The frame's start sample is the start of its first bit.
    private static func extractFrames(stream: BitStream, framesPerSecond: Int) -> [DecodedFrame] {
        let bits = stream.bits
        guard bits.count >= 80 else { return [] }
        var frames: [DecodedFrame] = []
        var end = 80
        while end <= bits.count {
            let window = Array(bits[(end - 80)..<end])
            if Array(window[64..<80]) == LTCFrame.syncWord {
                let frame = LTCFrame(bits: window)
                if frame.isWellFormed, let timecode = frame.timecode(framesPerSecond: framesPerSecond) {
                    frames.append(DecodedFrame(timecode: timecode, startSample: stream.startSamples[end - 80]))
                }
                end += 80
            } else {
                end += 1
            }
        }
        return frames
    }
}
