import Foundation

/// The project's timecode configuration, persisted in `.cuelist` (schema v10):
/// only the SMPTE framerate now lives here. Each clip carries its own
/// `startTimecodeFrames` on `MediaItem` (per-media start TC replaced the
/// project-wide `startOffsetFrames` in v9 → v10).
///
/// `timecode(atPlaybackSeconds:forItem:)` is the single source-of-truth mapping
/// the LTC generator and transport readout consume — pass the active item so
/// the result respects that clip's start TC.
struct ProjectTimecodeSettings: Codable, Equatable, Sendable {

    var framerate: SMPTEFramerate

    static let `default` = Self(framerate: .fps30)

    /// The timecode at a given playback position inside `item`, rounded to the
    /// nearest frame: `item.startTimecodeFrames + playbackPosition`. Negative
    /// `seconds` clamp to the item's start TC.
    func timecode(atPlaybackSeconds seconds: TimeInterval, forItem item: MediaItem) -> Timecode {
        let playbackFrames = Int((seconds * Double(framerate.framesPerSecond)).rounded())
        return Timecode(frameCount: item.startTimecodeFrames + max(0, playbackFrames), rate: framerate)
    }

    // Tolerate v9 payloads carrying a `startOffsetFrames` key: ignore it on
    // decode (the v9 → v10 migration has already lifted the value onto items).
    // Explicit CodingKeys prevents synthesized decoding from re-introducing the
    // field if a future addition shadows the same name.
    private enum CodingKeys: String, CodingKey { case framerate }
}
