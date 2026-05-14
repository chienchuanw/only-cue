import Foundation

/// v9 → current migration. Schema v10 dropped the project-wide
/// `timecodeSettings.startOffsetFrames` and fanned it onto each
/// `MediaItem.startTimecodeFrames`; schema v11 (this migration's target) moves
/// tempo from `MediaItem.tempoMap` onto per-cue `bpm`/`beatsPerBar`. A v9
/// project with offset = 0 and an empty tempo map round-trips to v11 cleanly.
extension ProjectModel {

    static func migrateFromV9(data: Data) throws -> ProjectModel {
        let legacy = try JSONDecoder().decode(LegacyV9.self, from: data)
        let offset = legacy.timecodeSettings.startOffsetFrames
        let defaultTypeID = legacy.cuePointTypes.first?.id
        let items = legacy.items.map { item -> MediaItem in
            let migratedCues = ProjectModel.applyLegacyTempoSectionsToCues(
                item.tempoMap.sections,
                cues: item.cues,
                defaultTypeID: defaultTypeID
            )
            return MediaItem(
                id: item.id,
                media: item.media,
                cues: migratedCues,
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
        let tempoMap: LegacyTempoMap
    }
}
