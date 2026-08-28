import Foundation

/// v21 → v22 migration (#782): `MediaItem` gains `colorHex`, the user-assigned
/// colour tag drawn as a leading stripe in the media panel. The field is
/// optional with a `nil` default, so a v21 document — which has no such key —
/// decodes straight into the current `MediaItem` with every item untagged.
/// That makes this structurally a re-stamp, exactly like v20 → v21.
extension ProjectModel {

    static func migrateFromV21(data: Data) throws -> ProjectModel {
        let legacy = try JSONDecoder().decode(LegacyV21.self, from: data)
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

    private struct LegacyV21: Decodable {
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
