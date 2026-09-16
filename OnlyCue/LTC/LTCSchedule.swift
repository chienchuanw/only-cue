import Foundation

/// The buffer plan for the LTC playback engine: a pure value type that maps a
/// sequential buffer index to the audio samples and the timecode that buffer
/// carries. `LTCAudioOutput` owns one of these and pumps `nextBuffer()` onto an
/// `AVAudioPlayerNode`; all the timecode/sample arithmetic lives here so that
/// side is just plumbing.
///
/// Each buffer is `framesPerBuffer` whole LTC frames, starting at
/// `startTimecode`. Within a buffer the biphase-mark polarity is threaded (via
/// `LTCFrameStream`); between buffers it resets to the canonical start level.
/// That reset changes nothing: every LTC frame ends at the level it started at,
/// because the bit-polarity-correction bit forces an even number of ones and so
/// an even number of mid-bit flips. The buffer seam is therefore byte-identical
/// to a threaded one, not merely tolerable — `golden/ltc-schedule-v1.json`'s
/// `bufferSeam` cases pin the samples either side of it.
///
/// What would be a real fault is an *inverted* seam, which drops a transition
/// and so misreads a bit; that is what the pinned seam window catches.
struct LTCSchedule {

    /// Timecode of the very first frame of buffer 0.
    let startTimecode: Timecode
    let sampleRate: Double
    /// Whole LTC frames per scheduled audio buffer (≥ 1).
    let framesPerBuffer: Int
    let amplitude: Float

    /// One scheduled buffer: its sequence index, the timecode of its first
    /// frame, and the audio samples.
    struct Buffer: Equatable, Sendable {
        let index: Int
        let timecode: Timecode
        let samples: [Float]
    }

    /// Buffers handed out by `nextBuffer()` so far.
    private(set) var emittedBuffers = 0

    init(
        startTimecode: Timecode,
        sampleRate: Double,
        framesPerBuffer: Int,
        amplitude: Float = LTCEncoder.defaultAmplitude
    ) {
        precondition(sampleRate > 0, "sample rate must be positive")
        precondition(framesPerBuffer >= 1, "a buffer holds at least one LTC frame")
        self.startTimecode = startTimecode
        self.sampleRate = sampleRate
        self.framesPerBuffer = framesPerBuffer
        self.amplitude = amplitude
    }

    private var framesPerSecond: Int { startTimecode.rate.framesPerSecond }

    /// Audio samples in one scheduled buffer (constant — `framesPerBuffer ×`
    /// the per-frame sample count).
    var samplesPerBuffer: Int {
        framesPerBuffer * Int((sampleRate / Double(framesPerSecond)).rounded())
    }

    /// Wall-clock duration of one scheduled buffer.
    var bufferDuration: TimeInterval {
        Double(framesPerBuffer) / Double(framesPerSecond)
    }

    /// Timecode at the start of buffer `index` (0-based).
    func timecode(forBufferIndex index: Int) -> Timecode {
        Timecode(frameCount: startTimecode.frameCount + max(0, index) * framesPerBuffer, rate: startTimecode.rate)
    }

    /// Samples for buffer `index` — a seamless `LTCFrameStream` run of
    /// `framesPerBuffer` frames starting at `timecode(forBufferIndex:)`.
    func samples(forBufferIndex index: Int) -> [Float] {
        LTCFrameStream(startTimecode: timecode(forBufferIndex: index), sampleRate: sampleRate, amplitude: amplitude)
            .samples(frameCount: framesPerBuffer)
    }

    /// Buffer `index` as a `Buffer` value.
    func buffer(at index: Int) -> Buffer {
        Buffer(index: index, timecode: timecode(forBufferIndex: index), samples: samples(forBufferIndex: index))
    }

    /// Hand out the next buffer in sequence (mutating — advances `emittedBuffers`).
    mutating func nextBuffer() -> Buffer {
        let result = buffer(at: emittedBuffers)
        emittedBuffers += 1
        return result
    }

    /// How many buffers should have been emitted to cover `elapsedSeconds` of
    /// playback plus `leadBuffers` of look-ahead headroom — the engine tops up
    /// `emittedBuffers` to this. `elapsedSeconds < 0` clamps to 0.
    func targetBufferCount(elapsedSeconds: TimeInterval, leadBuffers: Int) -> Int {
        let covering = Int((max(0, elapsedSeconds) / bufferDuration).rounded(.up))
        return covering + max(0, leadBuffers)
    }

    /// `framesPerBuffer` for a buffer of about `targetSeconds` at `rate` (≥ 1).
    static func framesPerBuffer(forTargetSeconds targetSeconds: TimeInterval, rate: SMPTEFramerate) -> Int {
        max(1, Int((max(0, targetSeconds) * Double(rate.framesPerSecond)).rounded()))
    }
}
