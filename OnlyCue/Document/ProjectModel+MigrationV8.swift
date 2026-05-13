import Foundation

/// v8 → current migration. Split into its own file because the migration chain
/// in `ProjectModel+Migration.swift` is at its size budget; each new schema
/// bump lives next to the dispatch as a sibling extension.
///
/// v8 was the schema before `Cue.cueNumber` widened to `Double?` (manual
/// numbering, issue #229). Every v8 cue carried a non-optional `Double`;
/// migration lifts each value into `.some(value)` so existing numbers are
/// preserved verbatim.
extension ProjectModel {

    static func migrateFromV8(data: Data) throws -> ProjectModel {
        let legacy = try JSONDecoder().decode(LegacyV8.self, from: data)
        // v8 documents converge on v10 directly: cueNumber widens to Double?
        // and the project-wide startOffsetFrames is fanned onto each item
        // (the same transformation v9 → v10 performs).
        let offset = legacy.timecodeSettings.startOffsetFrames
        return ProjectModel(
            schemaVersion: currentSchemaVersion,
            id: legacy.id,
            name: legacy.name,
            cuePointTypes: legacy.cuePointTypes,
            items: legacy.items.map { $0.toMediaItem(startTimecodeFrames: offset) },
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
        let tempoMap: TempoMap

        func toMediaItem(startTimecodeFrames: Int) -> MediaItem {
            MediaItem(
                id: id,
                media: media,
                cues: cues.map { $0.toCue() },
                tempoMap: tempoMap,
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
