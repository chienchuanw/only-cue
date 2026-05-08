import Foundation

extension CuePointType {

    /// Default palette cycled when the user adds a new Type via the Manage Types sheet.
    /// Mirrors the 8 named colors from the pre-PR-55 cue row palette so we keep visual
    /// continuity with the MVP era. Place a future "named palette" picker here too.
    static let defaultPalette: [String] = [
        "#FF6B6B", "#FFA94D", "#FFD93D", "#6BCB77",
        "#4ECDC4", "#4D96FF", "#9D7EE0", "#FF6FB5"
    ]
}
