import Foundation

/// Biphase-mark (FM) modulation of an LTC bit stream into a sequence of signal
/// *levels* — one per audio sample. The rule: a transition occurs at every bit
/// boundary, and an *additional* transition occurs at the midpoint of each `1`
/// bit (a `0` bit has no mid-bit transition). The caller supplies the integer
/// number of audio samples per *half*-bit period (= `sampleRate / (80 · fps · 2)`).
///
/// The fractional-rate handling (e.g. 24 fps at 48 kHz → 12.5 samples per
/// half-bit) and turning these levels into a real `Float` / `AVAudioPCMBuffer`
/// waveform belong with the Core Audio output leaf, which knows the device's
/// sample rate.
enum LTCBiphaseEncoder {

    /// - Parameters:
    ///   - bits: the LTC bit stream, transmission order.
    ///   - samplesPerHalfBit: audio samples per half-bit period (≥ 1).
    ///   - startLevel: the signal level *before* the first bit. The first bit's
    ///     boundary transition flips it, so the first emitted sample is `!startLevel`.
    /// - Returns: `samples` — one level per audio sample (`true` = +amplitude,
    ///   `false` = −amplitude); and `endLevel` — the level after the last
    ///   sample, so consecutive frames can be modulated continuously by passing
    ///   it back in as the next call's `startLevel`.
    static func levels(
        for bits: [Bool],
        samplesPerHalfBit: Int,
        startLevel: Bool = false
    ) -> (samples: [Bool], endLevel: Bool) {
        precondition(samplesPerHalfBit >= 1, "need at least one sample per half-bit")
        var level = startLevel
        var samples: [Bool] = []
        samples.reserveCapacity(bits.count * 2 * samplesPerHalfBit)
        for bit in bits {
            level.toggle()                                                  // bit-boundary transition (always)
            samples.append(contentsOf: repeatElement(level, count: samplesPerHalfBit))
            if bit { level.toggle() }                                       // mid-bit transition for a 1
            samples.append(contentsOf: repeatElement(level, count: samplesPerHalfBit))
        }
        return (samples, level)
    }
}
