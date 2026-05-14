import Foundation

/// v8 → current migration. v8 was the schema before `Cue.cueNumber` widened to
/// `Double?` (#229) and before `MediaItem.startTimecodeFrames` (#232). v8 docs
/// carried a project-wide `startOffsetFrames` and per-item `tempoMap`. This
/// migration lifts cue numbers into `.some(value)`, fans the project-wide
/// offset onto every item, and converts each `TempoSection` to per-cue tempo
/// (#244) — landing the doc on schema v11 directly.
extension ProjectModel {

    static func migrateFromV8(data: Data) throws -> ProjectModel {
        let legacy = try JSONDecoder().decode(LegacyV8.self, from: data)
        let offset = legacy.timecodeSettings.startOffsetFrames
        let defaultTypeID = legacy.cuePointTypes.first?.id
        return ProjectModel(
            schemaVersion: currentSchemaVersion,
            id: legacy.id,
            name: legacy.name,
            cuePointTypes: legacy.cuePointTypes,
            items: legacy.items.map { $0.toMediaItem(startTimecodeFrames: offset, defaultTypeID: defaultTypeID) },
            activeItemID: legacy.activeItemID,
            timecodeSettings: ProjectTimecodeSettings(framerate: legacy.timecodeSettings.framerate)
        )
    }

    private struct LegacyV8: Decodable {
        let schemaVersion: Int
        let id: UUID
        let name: String
        let cuePointTypes: [CuePointType]
        let items: [LegacyV8Item]
        let activeItemID: UUID?
        let timecodeSettings: LegacyPreV10TimecodeSettings
    }

    private struct LegacyV8Item: Decodable {
        let id: UUID
        let media: MediaReference
        let cues: [LegacyV8Cue]
        let tempoMap: LegacyTempoMap

        func toMediaItem(startTimecodeFrames: Int, defaultTypeID: UUID?) -> MediaItem {
            let baseCues = cues.map { $0.toCue() }
            let migratedCues = ProjectModel.applyLegacyTempoSectionsToCues(
                tempoMap.sections,
                cues: baseCues,
                defaultTypeID: defaultTypeID
            )
            return MediaItem(
                id: id,
                media: media,
                cues: migratedCues,
                startTimecodeFrames: startTimecodeFrames,
                ltcMuted: false
            )
        }
    }

    private struct LegacyV8Cue: Decodable {
        let id: UUID
        let typeID: UUID
        let cueNumber: Double
        let name: String
        let time: TimeInterval
        let notes: String
        let fadeTime: FadeTime

        func toCue() -> Cue {
            Cue(
                id: id,
                typeID: typeID,
                cueNumber: cueNumber,
                name: name,
                time: time,
                notes: notes,
                fadeTime: fadeTime
            )
        }
    }
}
