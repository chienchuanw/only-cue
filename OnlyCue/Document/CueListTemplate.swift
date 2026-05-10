import Foundation

/// Codable wrapper for a saved CuePointType set. Templates carry only the
/// Type list — never media, cues, or document metadata. The schemaVersion
/// gates future format evolution (e.g. adding hotkey conflict resolution).
struct CueListTemplate: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int = currentSchemaVersion
    var name: String
    var cuePointTypes: [CuePointType]
}
