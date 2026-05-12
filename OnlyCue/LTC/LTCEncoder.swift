import AVFoundation

/// Generates LTC audio: builds the 80-bit `LTCFrame` for a `Timecode`,
/// biphase-mark-modulates it, and lays the result down as `Float` PCM at a
/// given sample rate.
///
/// The 80-bit frame is split into 160 half-bit slots; slot `k` occupies samples
/// `[round(k·R) … round((k+1)·R))` where `R = sampleRate / (160·fps)`. So the
/// timing is exact at any sample rate — integer at 48 kHz for 24 / 25 / 30 fps,
/// and the rounding distributes the remainder cleanly when it isn't (e.g.
/// 44.1 kHz, or the 12.5-samples-per-half-bit case of 24 fps at 48 kHz, which is
/// integer at the *bit* level). `fps` here is the timeline rate — 30 for both
/// 30-ND and 30-DF (ADR-019: drop-frame is a labelling convention, not 29.97).
enum LTCEncoder {

    static let defaultAmplitude: Float = 0.8

    /// Float PCM samples (mono, `±amplitude`) for one LTC frame at `timecode`,
    /// continuous from `startLevel`. Returns the samples and the signal level
    /// after the last sample so consecutive frames can be modulated continuously
    /// (pass it back as the next call's `startLevel`).
    static func samples(
        for timecode: Timecode,
        sampleRate: Double,
        amplitude: Float = defaultAmplitude,
        startLevel: Bool = false
    ) -> (samples: [Float], endLevel: Bool) {
        precondition(sampleRate > 0, "sample rate must be positive")
        let frame = LTCFrame(timecode: timecode)
        let halfBitSamples = sampleRate / (160.0 * Double(timecode.rate.framesPerSecond))
        let high = amplitude
        let low = -amplitude

        var level = startLevel
        var samples: [Float] = []
        samples.reserveCapacity(Int((sampleRate / Double(timecode.rate.framesPerSecond)).rounded()) + 2)
        var slot = 0

        func emitSlot() {
            let start = Int((Double(slot) * halfBitSamples).rounded())
            let end = Int((Double(slot + 1) * halfBitSamples).rounded())
            samples.append(contentsOf: repeatElement(level ? high : low, count: max(0, end - start)))
            slot += 1
        }

        for bit in frame.bits {
            level.toggle()          // bit-boundary transition (always)
            emitSlot()
            if bit { level.toggle() }   // mid-bit transition for a 1
            emitSlot()
        }
        return (samples, level)
    }

    /// One LTC frame as an `AVAudioPCMBuffer` (`.pcmFormatFloat32`, mono, `sampleRate`).
    static func makeBuffer(
        for timecode: Timecode,
        sampleRate: Double,
        amplitude: Float = defaultAmplitude
    ) -> AVAudioPCMBuffer? {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)
        let pcm = samples(for: timecode, sampleRate: sampleRate, amplitude: amplitude).samples
        guard let format,
              !pcm.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(pcm.count)),
              let channel = buffer.floatChannelData else { return nil }
        buffer.frameLength = AVAudioFrameCount(pcm.count)
        pcm.withUnsafeBufferPointer { source in
            if let base = source.baseAddress { channel.pointee.update(from: base, count: pcm.count) }
        }
        return buffer
    }
}
