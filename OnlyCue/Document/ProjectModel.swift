import Foundation

struct ProjectModel: Codable, Equatable {

    static let currentSchemaVersion = 3

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

    static let defaultCuePointTypeName = "General"
    static let defaultCuePointTypeColorHex = "#4ECDC4"

    static func decode(from data: Data) throws -> ProjectModel {
        let probe = try JSONDecoder().decode(VersionProbe.self, from: data)
        switch probe.schemaVersion {
        case 1:
            return migrateFromV1(try JSONDecoder().decode(LegacyV1.self, from: data))
        case 2:
            return migrateFromV2(try JSONDecoder().decode(LegacyV2.self, from: data))
        case currentSchemaVersion:
            return try JSONDecoder().decode(ProjectModel.self, from: data)
        default:
            throw LoadError.unsupportedSchemaVersion(probe.schemaVersion)
        }
    }

    private struct VersionProbe: Decodable { let schemaVersion: Int }

    static func makeDefaultCuePointType() -> CuePointType {
        CuePointType(
            id: UUID(),
            name: defaultCuePointTypeName,
            colorHex: defaultCuePointTypeColorHex
        )
    }

    private struct LegacyV1: Decodable {
        let schemaVersion: Int
        let id: UUID
        let name: String
        let media: MediaReference?
        let cues: [LegacyCue]
    }

    private struct LegacyCue: Decodable {
        let id: UUID
        let name: String
        let time: TimeInterval
        let colorHex: String
        let notes: String

        func toCue(typeID: UUID) -> Cue {
            Cue(
                id: id,
                typeID: typeID,
                cueNumber: 0,
                name: name,
                time: time,
                colorHex: colorHex,
                notes: notes
            )
        }
    }

    private static func migrateFromV1(_ legacy: LegacyV1) -> ProjectModel {
        let defaultType = makeDefaultCuePointType()
        let items: [MediaItem]
        let active: UUID?
        if let media = legacy.media {
            let cues = legacy.cues.map { $0.toCue(typeID: defaultType.id) }
            let item = MediaItem(id: UUID(), media: media, cues: cues)
            items = [item]
            active = item.id
        } else {
            items = []
            active = nil
        }
        return ProjectModel(
            schemaVersion: currentSchemaVersion,
            id: legacy.id,
            name: legacy.name,
            cuePointTypes: [defaultType],
            items: items,
            activeItemID: active
        )
    }

    private struct LegacyV2: Decodable {
        let schemaVersion: Int
        let id: UUID
        let name: String
        let items: [LegacyV2Item]
        let activeItemID: UUID?
    }

    private struct LegacyV2Item: Decodable {
        let id: UUID
        let media: MediaReference
        let cues: [LegacyCue]
    }

    private static func migrateFromV2(_ legacy: LegacyV2) -> ProjectModel {
        let defaultType = makeDefaultCuePointType()
        let items = legacy.items.map { legacyItem in
            MediaItem(
                id: legacyItem.id,
                media: legacyItem.media,
                cues: legacyItem.cues.map { $0.toCue(typeID: defaultType.id) }
            )
        }
        return ProjectModel(
            schemaVersion: currentSchemaVersion,
            id: legacy.id,
            name: legacy.name,
            cuePointTypes: [defaultType],
            items: items,
            activeItemID: legacy.activeItemID
        )
    }
}
