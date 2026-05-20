import Foundation

/// v13 → v14 migration: `LyricLine.time` becomes optional (`nil` = unplaced).
/// A v13 document always wrote a concrete `time` on every lyric line, and no
/// other field changed shape — so a v13 payload decodes straight into the v14
/// model. The migration only re-stamps `schemaVersion`.
extension ProjectModel {

    static func migrateFromV13(data: Data) throws -> ProjectModel {
        var model = try JSONDecoder().decode(ProjectModel.self, from: data)
        model.schemaVersion = currentSchemaVersion
        return model
    }
}
