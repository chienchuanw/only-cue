import Foundation

struct ProjectModel: Codable, Equatable {

    static let currentSchemaVersion = 17

    var schemaVersion: Int
    var id: UUID
    var name: String
    var cuePointTypes: [CuePointType] = []
    var items: [MediaItem]
    var activeItemID: UUID?
    var timecodeSettings: ProjectTimecodeSettings = .default
    var playbackMode: PlaybackMode = .playOnce

    var defaultCuePointTypeID: UUID? { cuePointTypes.first?.id }

    var activeItem: MediaItem? {
        guard let id = activeItemID else { return nil }
        return items.first { $0.id == id }
    }

    var activeItemIndex: Int? {
        guard let id = activeItemID else { return nil }
        return items.firstIndex { $0.id == id }
    }

    /// Resolves the cue's display color from its `CuePointType`. Returns `nil` when the
    /// `typeID` doesn't match any Type in `cuePointTypes` (a programmer error in production
    /// but tolerated so views can fall back to `.accentColor`).
    func colorHex(for cue: Cue) -> String? {
        cuePointTypes.first(where: { $0.id == cue.typeID })?.colorHex
    }

    /// Returns the Type bound to a digit hotkey, if any. Used by the number-key
    /// cue-creation dispatch in `DocumentView`. Returns nil for unbound digits;
    /// the caller no-ops in that case.
    func cuePointType(forHotkey digit: Int) -> CuePointType? {
        cuePointTypes.first(where: { $0.hotkey == digit })
    }

    /// Counts every cue across every media item that references the given
    /// type. Used by the Manage Types row count badge (audit §10.1).
    func cueCount(forTypeID id: CuePointType.ID) -> Int {
        items.reduce(0) { acc, item in
            acc + item.cues.reduce(0) { $0 + ($1.typeID == id ? 1 : 0) }
        }
    }
}

/// End-of-media transport policy. Mutually exclusive — exactly one mode is
/// active per document. Default `.playOnce` preserves pre-v15 behavior.
enum PlaybackMode: String, Codable, Equatable, CaseIterable {
    case playOnce
    case loop
    case autoNext
}

extension ProjectModel {

    enum LoadError: Error, Equatable {
        case unsupportedSchemaVersion(Int)
    }

    static let defaultCuePointTypeName = "General"
    static let defaultCuePointTypeColorHex = "#4ECDC4"

    static func makeDefaultCuePointType() -> CuePointType {
        CuePointType(
            id: UUID(),
            name: defaultCuePointTypeName,
            colorHex: defaultCuePointTypeColorHex
        )
    }

    /// The canonical 5 cue types a fresh document is seeded with. Order is
    /// load-bearing — `General` leads so `defaultCuePointTypeID` (first
    /// element) keeps resolving to General for any caller that expects the
    /// historical default. Colors are drawn from `CuePointType.defaultPalette`
    /// so the design-system vocabulary stays consistent. Migrations from
    /// earlier schemas deliberately do NOT call this — they keep the user's
    /// own type set intact.
    static func makeCanonicalCuePointTypes() -> [CuePointType] {
        [
            CuePointType(id: UUID(), name: "General", colorHex: "#4ECDC4"), // teal
            CuePointType(id: UUID(), name: "Lighting", colorHex: "#FFD93D"), // yellow
            CuePointType(id: UUID(), name: "Sound", colorHex: "#4D96FF"), // blue
            CuePointType(id: UUID(), name: "Scene", colorHex: "#9D7EE0"), // purple
            CuePointType(id: UUID(), name: "Standby", colorHex: "#FFA94D")  // orange
        ]
    }
}
