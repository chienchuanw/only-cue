import Foundation

struct ProjectModel: Codable, Equatable {

    static let currentSchemaVersion = 4

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
        case 3:
            return migrateFromV3(try JSONDecoder().decode(LegacyV3.self, from: data))
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

    /// Seeds sequential `cueNumber`s (1-based, time-sorted) for documents that predate the field.
    private static func assignCueNumbersBySort(_ model: ProjectModel) -> ProjectModel {
        var copy = model
        for itemIndex in copy.items.indices {
            let sorted = copy.items[itemIndex].cues.sorted { $0.time < $1.time }
            copy.items[itemIndex].cues = sorted.enumerated().map { index, cue in
                var updated = cue
                updated.cueNumber = Double(index + 1)
                return updated
            }
        }
        return copy
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
                cueNumber: 0,  // overwritten by assignCueNumbersBySort
                name: name,
                time: time,
                colorHex: colorHex,
                notes: notes,
                fadeTime: .symmetric(0)
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
        let model = ProjectModel(
            schemaVersion: currentSchemaVersion,
            id: legacy.id,
            name: legacy.name,
            cuePointTypes: [defaultType],
            items: items,
            activeItemID: active
        )
        return assignCueNumbersBySort(model)
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
        let model = ProjectModel(
            schemaVersion: currentSchemaVersion,
            id: legacy.id,
            name: legacy.name,
            cuePointTypes: [defaultType],
            items: items,
            activeItemID: legacy.activeItemID
        )
        return assignCueNumbersBySort(model)
    }

    private struct LegacyV3: Decodable {
        let schemaVersion: Int
        let id: UUID
        let name: String
        let cuePointTypes: [CuePointType]
        let items: [LegacyV3Item]
        let activeItemID: UUID?
    }

    private struct LegacyV3Item: Decodable {
        let id: UUID
        let media: MediaReference
        let cues: [LegacyV3Cue]
    }

    private struct LegacyV3Cue: Decodable {
        let id: UUID
        let typeID: UUID
        let name: String
        let time: TimeInterval
        let colorHex: String
        let notes: String

        func toCue() -> Cue {
            Cue(
                id: id,
                typeID: typeID,
                cueNumber: 0,  // overwritten by assignCueNumbersBySort
                name: name,
                time: time,
                colorHex: colorHex,
                notes: notes,
                fadeTime: .symmetric(0)
            )
        }
    }

    private static func migrateFromV3(_ legacy: LegacyV3) -> ProjectModel {
        let items = legacy.items.map { legacyItem in
            MediaItem(
                id: legacyItem.id,
                media: legacyItem.media,
                cues: legacyItem.cues.map { $0.toCue() }
            )
        }
        let model = ProjectModel(
            schemaVersion: currentSchemaVersion,
            id: legacy.id,
            name: legacy.name,
            cuePointTypes: legacy.cuePointTypes,
            items: items,
            activeItemID: legacy.activeItemID
        )
        return assignCueNumbersBySort(model)
    }
}
