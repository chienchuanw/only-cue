import Foundation

/// v13 → v14 migration: `LyricLine.time` becomes optional (`nil` = unplaced).
/// A v13 document always wrote a concrete `time` on every lyric line, and no
/// other top-level field changed shape — so a v13 payload decodes straight
/// through the `LegacyV14` snapshot used by `migrateFromV14(data:)`, which
/// also seeds the post-v14 `playbackMode` default.
extension ProjectModel {

    static func migrateFromV13(data: Data) throws -> ProjectModel {
        try migrateFromV14(data: data)
    }
}
