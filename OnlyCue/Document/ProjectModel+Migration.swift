import Foundation

/// Schema-migration machinery for `ProjectModel`: one `LegacyVN` snapshot struct
/// and a `migrateFromVN` per historical schema version. Split out of
/// `ProjectModel.swift` because the chain grows by one struct + one function
/// with every schema bump.
extension ProjectModel {

    // swiftlint:disable:next cyclomatic_complexity
    static func decode(from data: Data) throws -> ProjectModel {
        let probe = try JSONDecoder().decode(VersionProbe.self, from: data)
        switch probe.schemaVersion {
        case 1:
            return migrateFromV1(try JSONDecoder().decode(LegacyV1.self, from: data))
        case 2:
            return migrateFromV2(try JSONDecoder().decode(LegacyV2.self, from: data))
        case 3:
            return migrateFromV3(try JSONDecoder().decode(LegacyV3.self, from: data))
        case 4:
            return migrateFromV4(try JSONDecoder().decode(LegacyV4.self, from: data))
        case 5:
            return migrateFromV5(try JSONDecoder().decode(LegacyV5.self, from: data))
        case 6:
            return migrateFromV6(try JSONDecoder().decode(LegacyV6.self, from: data))
        case 7:
            return migrateFromV7(try JSONDecoder().decode(LegacyV7.self, from: data))
        case 8:
            return try migrateFromV8(data: data)
        case 9:
            return try migrateFromV9(data: data)
        case currentSchemaVersion:
            return try JSONDecoder().decode(ProjectModel.self, from: data)
        default:
            throw LoadError.unsupportedSchemaVersion(probe.schemaVersion)
        }
    }

    private struct VersionProbe: Decodable { let schemaVersion: Int }

    /// Internal helper carrying every `Cue` field *except* `cueNumber`, which is assigned by
    /// `assignCueNumbersBySort` once all cues for an item are gathered. Exists so that a v1/v2/v3
    /// migration physically cannot construct a `Cue` without supplying a real `cueNumber` —
    /// a future migration that forgets to seed numbers fails to compile rather than silently
    /// producing zeros that would collide with legitimate `addCueAtPlayhead`-produced cueNumber 0s.
    private struct PendingCue {
        let id: UUID
        let typeID: UUID
        let time: TimeInterval
        let name: String
        let notes: String
        let fadeTime: FadeTime
    }

    /// Sorts pending cues by time and assigns 1-based sequential `cueNumber`s, producing the
    /// final `[Cue]` ready to plug into a `MediaItem`. Used by v1/v2/v3 migrations whose source
    /// documents predate `Cue.cueNumber`.
    ///
    /// When two cues share a `time`, the tie-break is `id.uuidString` lexicographic order.
    /// Swift's `Array.sorted(by:)` is *not* spec-guaranteed stable, so without this rule the
    /// `cueNumber` assigned to equal-time cues would be implementation-defined; with it,
    /// re-running the migration on the same JSON always produces the identical assignment.
    private static func assignCueNumbersBySort(_ pending: [PendingCue]) -> [Cue] {
        pending
            .sorted { lhs, rhs in
                if lhs.time != rhs.time { return lhs.time < rhs.time }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            .enumerated()
            .map { index, pendingCue in
                Cue(
                    id: pendingCue.id,
                    typeID: pendingCue.typeID,
                    cueNumber: Double(index + 1),
                    name: pendingCue.name,
                    time: pendingCue.time,
                    notes: pendingCue.notes,
                    fadeTime: pendingCue.fadeTime
                )
            }
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
        let notes: String

        func toPendingCue(typeID: UUID) -> PendingCue {
            PendingCue(
                id: id,
                typeID: typeID,
                time: time,
                name: name,
                notes: notes,
                fadeTime: .zero
            )
        }
    }

    private static func migrateFromV1(_ legacy: LegacyV1) -> ProjectModel {
        let defaultType = makeDefaultCuePointType()
        let items: [MediaItem]
        let active: UUID?
        if let media = legacy.media {
            let pending = legacy.cues.map { $0.toPendingCue(typeID: defaultType.id) }
            let item = MediaItem(id: UUID(), media: media, cues: assignCueNumbersBySort(pending))
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
            let pending = legacyItem.cues.map { $0.toPendingCue(typeID: defaultType.id) }
            return MediaItem(
                id: legacyItem.id,
                media: legacyItem.media,
                cues: assignCueNumbersBySort(pending)
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
        let notes: String

        func toPendingCue() -> PendingCue {
            PendingCue(
                id: id,
                typeID: typeID,
                time: time,
                name: name,
                notes: notes,
                fadeTime: .zero
            )
        }
    }

    private static func migrateFromV3(_ legacy: LegacyV3) -> ProjectModel {
        let items = legacy.items.map { legacyItem in
            let pending = legacyItem.cues.map { $0.toPendingCue() }
            return MediaItem(
                id: legacyItem.id,
                media: legacyItem.media,
                cues: assignCueNumbersBySort(pending)
            )
        }
        return ProjectModel(
            schemaVersion: currentSchemaVersion,
            id: legacy.id,
            name: legacy.name,
            cuePointTypes: legacy.cuePointTypes,
            items: items,
            activeItemID: legacy.activeItemID
        )
    }

    private struct LegacyV4: Decodable {
        let schemaVersion: Int
        let id: UUID
        let name: String
        let cuePointTypes: [CuePointType]
        let items: [LegacyV4Item]
        let activeItemID: UUID?
    }

    private struct LegacyV4Item: Decodable {
        let id: UUID
        let media: MediaReference
        let cues: [LegacyV4Cue]
    }

    private struct LegacyV4Cue: Decodable {
        let id: UUID
        let typeID: UUID
        let cueNumber: Double
        let name: String
        let time: TimeInterval
        let notes: String

        func toCue() -> Cue {
            Cue(
                id: id,
                typeID: typeID,
                cueNumber: cueNumber,
                name: name,
                time: time,
                notes: notes,
                fadeTime: .zero
            )
        }
    }

    private static func migrateFromV4(_ legacy: LegacyV4) -> ProjectModel {
        let items = legacy.items.map { legacyItem in
            MediaItem(
                id: legacyItem.id,
                media: legacyItem.media,
                cues: legacyItem.cues.map { $0.toCue() }
            )
        }
        return ProjectModel(
            schemaVersion: currentSchemaVersion,
            id: legacy.id,
            name: legacy.name,
            cuePointTypes: legacy.cuePointTypes,
            items: items,
            activeItemID: legacy.activeItemID
        )
    }

    private struct LegacyV5: Decodable {
        let schemaVersion: Int
        let id: UUID
        let name: String
        let cuePointTypes: [CuePointType]
        let items: [LegacyV5Item]
        let activeItemID: UUID?
    }

    private struct LegacyV5Item: Decodable {
        let id: UUID
        let media: MediaReference
        let cues: [LegacyV5Cue]
    }

    private struct LegacyV5Cue: Decodable {
        let id: UUID
        let typeID: UUID
        let cueNumber: Double
        let name: String
        let time: TimeInterval
        let notes: String
        let fadeTime: FadeTime

        func toCue() -> Cue {
            Cue(
                id: id,
                typeID: typeID,
                cueNumber: cueNumber,
                name: name,
                time: time,
                notes: notes,
                fadeTime: fadeTime
            )
        }
    }

    private static func migrateFromV5(_ legacy: LegacyV5) -> ProjectModel {
        let items = legacy.items.map { legacyItem in
            MediaItem(
                id: legacyItem.id,
                media: legacyItem.media,
                cues: legacyItem.cues.map { $0.toCue() }
            )
        }
        return ProjectModel(
            schemaVersion: currentSchemaVersion,
            id: legacy.id,
            name: legacy.name,
            cuePointTypes: legacy.cuePointTypes,
            items: items,
            activeItemID: legacy.activeItemID
        )
    }

    /// A media-item snapshot for the v6 and v7 schemas — both predate
    /// `MediaItem.tempoMap` (epic #199), and `MediaItem`'s synthesized `Decodable`
    /// does *not* fall back to property defaults for missing keys, so decoding
    /// those documents needs a struct that matches their on-disk item shape.
    private struct LegacyMediaItemPreV8: Decodable {
        let id: UUID
        let media: MediaReference
        let cues: [Cue]

        func toMediaItem(startTimecodeFrames: Int = 0) -> MediaItem {
            MediaItem(
                id: id,
                media: media,
                cues: cues,
                tempoMap: TempoMap(),
                startTimecodeFrames: startTimecodeFrames,
                ltcMuted: false
            )
        }
    }

    /// v6 = the schema before `timecodeSettings` (epic #33 leaf 4) and before
    /// `tempoMap`. Migration seeds the default timecode settings + empty tempo maps.
    private struct LegacyV6: Decodable {
        let schemaVersion: Int
        let id: UUID
        let name: String
        let cuePointTypes: [CuePointType]
        let items: [LegacyMediaItemPreV8]
        let activeItemID: UUID?
    }

    private static func migrateFromV6(_ legacy: LegacyV6) -> ProjectModel {
        ProjectModel(
            schemaVersion: currentSchemaVersion,
            id: legacy.id,
            name: legacy.name,
            cuePointTypes: legacy.cuePointTypes,
            items: legacy.items.map { $0.toMediaItem() },
            activeItemID: legacy.activeItemID,
            timecodeSettings: .default
        )
    }

    /// v7 = the schema before `MediaItem.tempoMap` (epic #199). Migration seeds
    /// an empty tempo map on every item and fans the project-wide
    /// `startOffsetFrames` (dropped in v10) onto each item's
    /// `startTimecodeFrames`.
    private struct LegacyV7: Decodable {
        let schemaVersion: Int
        let id: UUID
        let name: String
        let cuePointTypes: [CuePointType]
        let items: [LegacyMediaItemPreV8]
        let activeItemID: UUID?
        let timecodeSettings: LegacyPreV10TimecodeSettings
    }

    private static func migrateFromV7(_ legacy: LegacyV7) -> ProjectModel {
        let offset = legacy.timecodeSettings.startOffsetFrames
        return ProjectModel(
            schemaVersion: currentSchemaVersion,
            id: legacy.id,
            name: legacy.name,
            cuePointTypes: legacy.cuePointTypes,
            items: legacy.items.map { $0.toMediaItem(startTimecodeFrames: offset) },
            activeItemID: legacy.activeItemID,
            timecodeSettings: ProjectTimecodeSettings(framerate: legacy.timecodeSettings.framerate)
        )
    }

}
