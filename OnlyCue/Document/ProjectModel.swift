import Foundation

struct ProjectModel: Codable, Equatable {

    static let currentSchemaVersion = 2

    var schemaVersion: Int
    var id: UUID
    var name: String
    var items: [MediaItem]
    var activeItemID: UUID?

    var activeItem: MediaItem? {
        guard let id = activeItemID else { return nil }
        return items.first { $0.id == id }
    }

    var activeItemIndex: Int? {
        guard let id = activeItemID else { return nil }
        return items.firstIndex { $0.id == id }
    }
}

extension ProjectModel {

    enum LoadError: Error, Equatable {
        case unsupportedSchemaVersion(Int)
    }

    static func decode(from data: Data) throws -> ProjectModel {
        let probe = try JSONDecoder().decode(VersionProbe.self, from: data)
        switch probe.schemaVersion {
        case 1:
            let v1 = try JSONDecoder().decode(V1.self, from: data)
            return migrateFromV1(v1)
        case currentSchemaVersion:
            return try JSONDecoder().decode(ProjectModel.self, from: data)
        default:
            throw LoadError.unsupportedSchemaVersion(probe.schemaVersion)
        }
    }

    private struct VersionProbe: Decodable { let schemaVersion: Int }

    private struct V1: Decodable {
        let schemaVersion: Int
        let id: UUID
        let name: String
        let media: MediaReference?
        let cues: [Cue]
    }

    private static func migrateFromV1(_ v1: V1) -> ProjectModel {
        if let media = v1.media {
            let item = MediaItem(id: UUID(), media: media, cues: v1.cues)
            return ProjectModel(
                schemaVersion: currentSchemaVersion,
                id: v1.id,
                name: v1.name,
                items: [item],
                activeItemID: item.id
            )
        }
        return ProjectModel(
            schemaVersion: currentSchemaVersion,
            id: v1.id,
            name: v1.name,
            items: [],
            activeItemID: nil
        )
    }
}
