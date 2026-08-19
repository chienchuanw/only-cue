import Foundation

/// v20 → v21 migration (#764): `MA2PushTarget.executorPage` / `executorNumber` become
/// optional (`nil` = leave the sequence unassigned). A v20 document always stored both as
/// 1-based `Int`s, which decode straight into the new `Int?` fields, so this is
/// structurally a no-op — decode a `LegacyV20` snapshot and re-stamp the current schema
/// version. `items: [MediaItem]` decodes directly because the only change is inside the
/// nested `MA2PushTarget`, and an `Int` decodes into an `Int?` unchanged.
extension ProjectModel {

    static func migrateFromV20(data: Data) throws -> ProjectModel {
        let legacy = try JSONDecoder().decode(LegacyV20.self, from: data)
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

    private struct LegacyV20: Decodable {
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
