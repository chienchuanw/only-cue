import Foundation

/// v17 → v18 migration: `MA2PushTarget` gains the optional `sequenceName`
/// (#686, defaults to nil). A v17 document never wrote it, so this is
/// structurally a no-op — decode a `LegacyV17` snapshot and re-stamp the
/// current schema version. `items: [MediaItem]` decodes directly because the
/// only change is a nested optional field (missing key → nil).
extension ProjectModel {

    static func migrateFromV17(data: Data) throws -> ProjectModel {
        let legacy = try JSONDecoder().decode(LegacyV17.self, from: data)
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

    private struct LegacyV17: Decodable {
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
