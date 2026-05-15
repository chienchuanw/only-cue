import Foundation

/// v11 → v12 migration: adds `MediaItem.alternateName` (defaults to nil).
/// Additive only — no data is rewritten; every other field is decoded as-is.
extension ProjectModel {

    static func migrateFromV11(data: Data) throws -> ProjectModel {
        let legacy = try JSONDecoder().decode(LegacyV11.self, from: data)
        return ProjectModel(
            schemaVersion: currentSchemaVersion,
            id: legacy.id,
            name: legacy.name,
            cuePointTypes: legacy.cuePointTypes,
            items: legacy.items.map { $0.toMediaItem() },
            activeItemID: legacy.activeItemID,
            timecodeSettings: legacy.timecodeSettings
        )
    }

    private struct LegacyV11: Decodable {
        let schemaVersion: Int
        let id: UUID
        let name: String
        let cuePointTypes: [CuePointType]
        let items: [LegacyV11Item]
        let activeItemID: UUID?
        let timecodeSettings: ProjectTimecodeSettings
    }

    private struct LegacyV11Item: Decodable {
        let id: UUID
        let media: MediaReference
        let cues: [Cue]
        let startTimecodeFrames: Int
        let ltcMuted: Bool

        func toMediaItem() -> MediaItem {
            MediaItem(
                id: id,
                media: media,
                cues: cues,
                startTimecodeFrames: startTimecodeFrames,
                ltcMuted: ltcMuted,
                alternateName: nil
            )
        }
    }
}
