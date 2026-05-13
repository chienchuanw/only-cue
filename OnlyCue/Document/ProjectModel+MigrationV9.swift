import Foundation

/// v9 → current (v10) migration. Schema v10 drops the project-wide
/// `timecodeSettings.startOffsetFrames` and fans the value onto each
/// `MediaItem.startTimecodeFrames`; `MediaItem.ltcMuted` defaults to `false`.
/// A v9 project with offset = 0 round-trips to a v10 with every item at 0.
extension ProjectModel {

    static func migrateFromV9(data: Data) throws -> ProjectModel {
        let legacy = try JSONDecoder().decode(LegacyV9.self, from: data)
        let offset = legacy.timecodeSettings.startOffsetFrames
        let items = legacy.items.map { item in
            MediaItem(
                id: item.id,
                media: item.media,
                cues: item.cues,
                tempoMap: item.tempoMap,
                startTimecodeFrames: offset,
                ltcMuted: false
            )
        }
        return ProjectModel(
            schemaVersion: currentSchemaVersion,
            id: legacy.id,
            name: legacy.name,
            cuePointTypes: legacy.cuePointTypes,
            items: items,
            activeItemID: legacy.activeItemID,
            timecodeSettings: ProjectTimecodeSettings(framerate: legacy.timecodeSettings.framerate)
        )
    }

    private struct LegacyV9: Decodable {
        let schemaVersion: Int
        let id: UUID
        let name: String
        let cuePointTypes: [CuePointType]
        let items: [LegacyV9Item]
        let activeItemID: UUID?
        let timecodeSettings: LegacyV9TimecodeSettings
    }

    private struct LegacyV9Item: Decodable {
        let id: UUID
        let media: MediaReference
        let cues: [Cue]
        let tempoMap: TempoMap
    }

    /// Captures the v9 shape of `ProjectTimecodeSettings` (framerate + the
    /// dropped `startOffsetFrames`). The current struct decodes only
    /// `framerate`; this legacy shape is what the migration reads from.
    private struct LegacyV9TimecodeSettings: Decodable {
        let framerate: SMPTEFramerate
        let startOffsetFrames: Int

        private enum CodingKeys: String, CodingKey { case framerate, startOffsetFrames }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            framerate = try container.decode(SMPTEFramerate.self, forKey: .framerate)
            startOffsetFrames = try container.decodeIfPresent(Int.self, forKey: .startOffsetFrames) ?? 0
        }
    }
}
