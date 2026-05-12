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
struct StripedTimecodeTrack: Equatable, Sendable {

    /// Timecode at `anchorPlaybackSeconds` (the start of the first decoded frame).
    let anchorTimecode: Timecode
    /// Playback position, in seconds, that `anchorTimecode` corresponds to.
    let anchorPlaybackSeconds: TimeInterval

    init(anchorTimecode: Timecode, anchorPlaybackSeconds: TimeInterval) {
        self.anchorTimecode = anchorTimecode
        self.anchorPlaybackSeconds = anchorPlaybackSeconds
    }

    /// Anchor on the first decoded frame. `nil` if no frames were recovered (or
    /// `sampleRate <= 0`) — i.e. the file has no readable LTC.
    init?(decodedFrames: [LTCDecoder.DecodedFrame], sampleRate: Double) {
        guard let first = decodedFrames.first, sampleRate > 0 else { return nil }
        self.init(anchorTimecode: first.timecode, anchorPlaybackSeconds: Double(first.startSample) / sampleRate)
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
