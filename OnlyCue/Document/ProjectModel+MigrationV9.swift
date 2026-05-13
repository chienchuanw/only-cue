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
        let timecodeSettings: LegacyPreV10TimecodeSettings
    }

    private struct LegacyV9Item: Decodable {
        let id: UUID
        let media: MediaReference
        let cues: [Cue]
        let tempoMap: TempoMap
    }
}
