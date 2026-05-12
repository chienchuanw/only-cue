import Foundation

/// The project's timecode configuration, persisted in `.cuelist` (schema v7):
/// which SMPTE framerate the project runs at, and where its timecode starts
/// (`startOffsetFrames` is the start timecode expressed as a count of frames
/// since `00:00:00:00`, so e.g. a 25 fps project starting at `01:00:00:00` has
/// `framerate = .fps25`, `startOffsetFrames = 90_000`).
///
/// The derived timecodes here are what the LTC generator and the Audio &
/// Timecode preferences pane consume — the pane edits `framerate` /
/// `startOffsetFrames`; the generator maps a playback position to a `Timecode`.
struct ProjectTimecodeSettings: Codable, Equatable, Sendable {

    var framerate: SMPTEFramerate
    var startOffsetFrames: Int

    static let `default` = Self(framerate: .fps30, startOffsetFrames: 0)

    /// The project's start timecode (the offset from `00:00:00:00`).
    var startTimecode: Timecode {
        Timecode(frameCount: startOffsetFrames, rate: framerate)
    }

    /// The timecode at a given playback position (seconds into the timeline),
    /// rounded to the nearest frame: `startOffset + playbackPosition`.
    func timecode(atPlaybackSeconds seconds: TimeInterval) -> Timecode {
        let playbackFrames = Int((seconds * Double(framerate.framesPerSecond)).rounded())
        return Timecode(frameCount: startOffsetFrames + max(0, playbackFrames), rate: framerate)
    }
}
