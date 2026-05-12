import Foundation

struct ProjectModel: Codable, Equatable {

    static let currentSchemaVersion = 8

    var schemaVersion: Int
    var id: UUID
    var name: String
    var cuePointTypes: [CuePointType] = []
    var items: [MediaItem]
    var activeItemID: UUID?
    var timecodeSettings: ProjectTimecodeSettings = .default

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
}
