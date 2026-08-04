import Foundation

/// v18 → v19 migration: `MediaItem` gains `playsOriginalSourceAudio`
/// (#715, defaults to false — music-only). A v18 document never wrote it, so
/// this is structurally a no-op — decode a `LegacyV18` snapshot and re-stamp
/// the current schema version. `items: [MediaItem]` decodes directly because
/// the only change is a new Bool field with a property default (missing key → false).
extension ProjectModel {

    static func migrateFromV18(data: Data) throws -> ProjectModel {
        let legacy = try JSONDecoder().decode(LegacyV18.self, from: data)
        return ProjectModel(
            schemaVersion: currentSchemaVersion,
            id: legacy.id,
            name: legacy.name,
            cuePointTypes: legacy.cuePointTypes,
            items: legacy.items,
            activeItemID: legacy.activeItemID,
            timecodeSettings: legacy.timecodeSettings,
            playbackMode: legacy.playbackMode
        )
    }

    private struct LegacyV18: Decodable {
        let schemaVersion: Int
        let id: UUID
        let name: String
        let cuePointTypes: [CuePointType]
        let items: [MediaItem]
        let activeItemID: UUID?
        let timecodeSettings: ProjectTimecodeSettings
        let playbackMode: PlaybackMode
    }
}
