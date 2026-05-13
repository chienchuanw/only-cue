import Foundation

/// The pre-v10 shape of `ProjectTimecodeSettings`: framerate +
/// `startOffsetFrames` (now lifted onto each `MediaItem.startTimecodeFrames`).
/// Used by every pre-v10 migration's `Legacy` snapshot so the offset survives
/// the chain into the v10 fan-out. File-internal access (no `fileprivate`)
/// so V7/V8/V9 migrations can share a single decoder.
struct LegacyPreV10TimecodeSettings: Decodable {
    let framerate: SMPTEFramerate
    let startOffsetFrames: Int

    private enum CodingKeys: String, CodingKey { case framerate, startOffsetFrames }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        framerate = try container.decode(SMPTEFramerate.self, forKey: .framerate)
        startOffsetFrames = try container.decodeIfPresent(Int.self, forKey: .startOffsetFrames) ?? 0
    }
}
