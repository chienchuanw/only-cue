import Foundation

extension ProjectModel {

    /// v22 -> v23 (#793): `MediaItem.ltcChannelSelection` arrives, and
    /// `StripedTimecodeTrack` gains optional `validFrom` / `validUntil`.
    /// Both are absent-means-default, so this is a pure re-stamp: items
    /// decode with `.auto` and remembered tracks decode unbounded, which
    /// is the behaviour those documents had.
    static func migrateFromV22(data: Data) throws -> ProjectModel {
        let legacy = try JSONDecoder().decode(LegacyV22.self, from: data)
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

    private struct LegacyV22: Decodable {
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
