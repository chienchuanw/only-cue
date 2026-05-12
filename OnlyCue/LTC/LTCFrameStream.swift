import Foundation

/// A continuous LTC audio stream — successive 80-bit SMPTE frames starting at
/// `startTimecode`, biphase-mark polarity threaded across the frame boundaries
/// so the concatenated output is a seamless waveform. Pure value type; the
/// `AVAudioEngine` that schedules these samples onto an output device is a
/// separate concern (a later leaf of epic #33).
struct LTCFrameStream {

    let startTimecode: Timecode
    let sampleRate: Double
    var amplitude: Float

    init(
        startTimecode: Timecode,
        sampleRate: Double,
        amplitude: Float = LTCEncoder.defaultAmplitude
    ) {
        precondition(sampleRate > 0, "sample rate must be positive")
        self.startTimecode = startTimecode
        self.sampleRate = sampleRate
        self.amplitude = amplitude
    }

    var framesPerSecond: Int { startTimecode.rate.framesPerSecond }

    /// Samples in one LTC frame at this stream's sample rate (constant across
    /// frames — `round(sampleRate / fps)`).
    var samplesPerFrame: Int { Int((sampleRate / Double(framesPerSecond)).rounded()) }

    /// The timecode of the frame `offset` frames after the start (negative
    /// offsets clamp to the start).
    func timecode(atFrameOffset offset: Int) -> Timecode {
        Timecode(frameCount: startTimecode.frameCount + max(0, offset), rate: startTimecode.rate)
    }

    /// Float PCM (mono, `±amplitude`) for `count` consecutive frames beginning
    /// at `startTimecode`, with biphase polarity carried across the joins so the
    /// result has no boundary glitch. Empty when `count <= 0`.
    func samples(frameCount count: Int) -> [Float] {
        guard count > 0 else { return [] }
        var output: [Float] = []
        output.reserveCapacity(count * samplesPerFrame + count)
        var level = false
        for offset in 0..<count {
            let (frameSamples, endLevel) = LTCEncoder.samples(
                for: timecode(atFrameOffset: offset),
                sampleRate: sampleRate,
                amplitude: amplitude,
                startLevel: level
            )
            output.append(contentsOf: frameSamples)
            level = endLevel
        }
        return output
    }
}
