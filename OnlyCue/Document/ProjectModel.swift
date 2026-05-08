import Foundation

struct ProjectModel: Codable, Equatable {

    static let currentSchemaVersion = 2

    var schemaVersion: Int
    var id: UUID
    var name: String
    var cuePointTypes: [CuePointType] = []
    var items: [MediaItem]
    var activeItemID: UUID?

    var defaultCuePointTypeID: UUID? { cuePointTypes.first?.id }

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
            let legacy = try JSONDecoder().decode(LegacyV1.self, from: data)
            return migrateFromV1(legacy)
        case currentSchemaVersion:
            return try JSONDecoder().decode(ProjectModel.self, from: data)
        default:
            throw LoadError.unsupportedSchemaVersion(probe.schemaVersion)
        }
    }

    private struct VersionProbe: Decodable { let schemaVersion: Int }

    private struct LegacyV1: Decodable {
        let schemaVersion: Int
        let id: UUID
        let name: String
        let media: MediaReference?
        let cues: [LegacyV1Cue]
    }

    private struct LegacyV1Cue: Decodable {
        let id: UUID
        let name: String
        let time: TimeInterval
        let colorHex: String
        let notes: String

        func toCue(typeID: UUID) -> Cue {
            Cue(id: id, typeID: typeID, name: name, time: time, colorHex: colorHex, notes: notes)
        }
    }

    private static func migrateFromV1(_ legacy: LegacyV1) -> ProjectModel {
        let placeholderTypeID = UUID()
        if let media = legacy.media {
            let cues = legacy.cues.map { $0.toCue(typeID: placeholderTypeID) }
            let item = MediaItem(id: UUID(), media: media, cues: cues)
            return ProjectModel(
                schemaVersion: currentSchemaVersion,
                id: legacy.id,
                name: legacy.name,
                items: [item],
                activeItemID: item.id
            )
        }
        return ProjectModel(
            schemaVersion: currentSchemaVersion,
            id: legacy.id,
            name: legacy.name,
            items: [],
            activeItemID: nil
        )
    }
}
