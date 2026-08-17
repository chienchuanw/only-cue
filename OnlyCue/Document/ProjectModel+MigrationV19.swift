import Foundation

/// v19 → v20 migration: `MediaItem` gains `rememberedLTC` (#754, defaults to nil).
/// A v19 document never wrote it, so this is structurally a no-op — decode a
/// `LegacyV19` snapshot and re-stamp the current schema version. `items:
/// [MediaItem]` decodes directly because the only change is a new optional field
/// (`MediaItem` decodes it via `decodeIfPresent`; missing key → nil).
extension ProjectModel {

    static func migrateFromV19(data: Data) throws -> ProjectModel {
        let legacy = try JSONDecoder().decode(LegacyV19.self, from: data)
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

    private struct LegacyV19: Decodable {
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
