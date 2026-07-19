import Foundation

/// v16 → v17 migration: `MediaItem` gains the optional `ma2PushTarget` (#683,
/// defaults to nil). A v16 document never wrote it, so the migration is
/// structurally a no-op — decode a `LegacyV16` snapshot and re-stamp the
/// current schema version. `items: [MediaItem]` decodes directly because the
/// only change is an optional field (missing key → nil).
extension ProjectModel {

    static func migrateFromV16(data: Data) throws -> ProjectModel {
        let legacy = try JSONDecoder().decode(LegacyV16.self, from: data)
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

    private struct LegacyV16: Decodable {
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
