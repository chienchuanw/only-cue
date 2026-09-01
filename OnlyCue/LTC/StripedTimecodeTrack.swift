import Foundation

/// The SMPTE timecode striped onto a media file's audio, expressed as an anchor
/// (timecode at a known playback position) plus the assumption that LTC is
/// linear — so any other playback position extrapolates exactly. Built from the
/// frames `LTCDecoder` recovers off the file's first audio track (only the first
/// recovered frame is needed; the rest of the read just confirms there *is* a
/// signal).
///
/// Used by the transport bar's SMPTE readout: when a `StripedTimecodeTrack` is
/// present it takes priority over `ProjectTimecodeSettings`. The generator still
/// emits the project-settings timecode (the epic's "the generator can override
/// it"). Slaving playback *position* to incoming LTC is out of scope.
struct StripedTimecodeTrack: Equatable, Sendable, Codable {

    /// Timecode at `anchorPlaybackSeconds` (the start of the first decoded frame).
    let anchorTimecode: Timecode
    /// Playback position, in seconds, that `anchorTimecode` corresponds to.
    let anchorPlaybackSeconds: TimeInterval
    /// Zero-based index of the audio channel that carries the LTC signal.
    /// Used by downstream features (music-only playback, music-only waveform) to
    /// exclude the timecode channel from the output.
    let ltcChannel: Int

    /// First playback second at which this track's timecode is real.
    /// `nil` means unbounded — either not yet measured (between Phase 1 and
    /// Phase 2 completing) or loaded from a document saved before #793.
    let validFrom: TimeInterval?

    /// Last playback second at which this track's timecode is real.
    /// `nil` means unbounded, exactly as `validFrom`.
    let validUntil: TimeInterval?

    init(
        anchorTimecode: Timecode,
        anchorPlaybackSeconds: TimeInterval,
        ltcChannel: Int = 0,
        validFrom: TimeInterval? = nil,
        validUntil: TimeInterval? = nil
    ) {
        self.anchorTimecode = anchorTimecode
        self.anchorPlaybackSeconds = anchorPlaybackSeconds
        self.ltcChannel = ltcChannel
        self.validFrom = validFrom
        self.validUntil = validUntil
    }

    /// Whether the timecode this track reports at `seconds` was actually
    /// measured from the file, as opposed to extrapolated past the end of
    /// the stripe. Unbounded on either side means "assume valid".
    func isValid(atPlaybackSeconds seconds: TimeInterval) -> Bool {
        if let validFrom, seconds < validFrom { return false }
        if let validUntil, seconds > validUntil { return false }
        return true
    }

    /// Anchor on the detected channel's first decoded frame. `nil` if no frames
    /// were recovered (or `sampleRate <= 0`) — i.e. the file has no readable LTC.
    init?(detection: LTCAudioReader.DetectionResult, sampleRate: Double) {
        guard let first = detection.frames.first, sampleRate > 0 else { return nil }
        // Phase 1 scans only the head of the file: it can bound the start but
        // not the end, so validUntil stays nil (unbounded) until the full-file
        // pass measures it.
        let start = Double(first.startSample) / sampleRate
        self.init(
            anchorTimecode: first.timecode,
            anchorPlaybackSeconds: start,
            ltcChannel: detection.channel,
            validFrom: start
        )
    }

    /// Anchor on the first decoded frame. `nil` if no frames were recovered (or
    /// `sampleRate <= 0`) — i.e. the file has no readable LTC.
    ///
    /// - Note: This initialiser does not know which channel the frames came from;
    ///   it defaults `ltcChannel` to 0. Prefer `init?(detection:sampleRate:)` when
    ///   the channel index is available (i.e. from `LTCAudioReader.detectTimecodes`).
    init?(decodedFrames: [LTCDecoder.DecodedFrame], sampleRate: Double) {
        guard let first = decodedFrames.first, sampleRate > 0 else { return nil }
        // Phase 1 sees only the head of the file: it can bound the start but
        // not the end, so validUntil stays nil (unbounded) until the full-file
        // pass in MediaImporter measures it.
        self.init(
            anchorTimecode: first.timecode,
            anchorPlaybackSeconds: Double(first.startSample) / sampleRate,
            validFrom: Double(first.startSample) / sampleRate,
            validUntil: nil
        )
    }

    /// Builds a track from a decode of the entire file, so both bounds are
    /// measured rather than assumed. `validUntil` extends one frame past the
    /// last frame's start, because that frame occupies real time.
    init?(fullFileFrames frames: [LTCDecoder.DecodedFrame], channel: Int, sampleRate: Double) {
        guard let first = frames.first, let last = frames.last, sampleRate > 0 else { return nil }
        self.anchorTimecode = first.timecode
        self.anchorPlaybackSeconds = Double(first.startSample) / sampleRate
        self.ltcChannel = channel
        self.validFrom = Double(first.startSample) / sampleRate
        self.validUntil = Double(last.startSample) / sampleRate
            + 1.0 / Double(last.timecode.rate.framesPerSecond)
    }

    /// The striped timecode at `seconds` of playback — `anchorTimecode` shifted
    /// by the elapsed-frame count (rounded). `Timecode(frameCount:rate:)` clamps
    /// at 0 and wraps at 24 h, matching the rest of the timecode model.
    func timecode(atPlaybackSeconds seconds: TimeInterval) -> Timecode {
        let framesPerSecond = anchorTimecode.rate.framesPerSecond
        let frameDelta = Int(((seconds - anchorPlaybackSeconds) * Double(framesPerSecond)).rounded())
        return Timecode(frameCount: anchorTimecode.frameCount + frameDelta, rate: anchorTimecode.rate)
    }
}
