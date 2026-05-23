import Foundation

/// v14 → v15 migration: adds `ProjectModel.playbackMode` (defaults to
/// `.playOnce`). Decodes a `LegacyV14` snapshot that lacks `playbackMode`,
/// then constructs a fresh v15 `ProjectModel` so the field's default value
/// applies. Every other field is forwarded as-is.
extension ProjectModel {

    static func migrateFromV14(data: Data) throws -> ProjectModel {
        let legacy = try JSONDecoder().decode(LegacyV14.self, from: data)
        return ProjectModel(
            schemaVersion: currentSchemaVersion,
            id: legacy.id,
            name: legacy.name,
            cuePointTypes: legacy.cuePointTypes,
            items: legacy.items,
            activeItemID: legacy.activeItemID,
            timecodeSettings: legacy.timecodeSettings
        )
    }

    private struct LegacyV14: Decodable {
        let schemaVersion: Int
        let id: UUID
        let name: String
        let cuePointTypes: [CuePointType]
        let items: [MediaItem]
        let activeItemID: UUID?
        let timecodeSettings: ProjectTimecodeSettings
    }
}
