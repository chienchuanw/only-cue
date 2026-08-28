import Foundation

extension CuePointType {

    /// The palette as `(hex, name)` pairs — the single source of truth for both
    /// consumers: the Manage Types sheet cycles it for new Types, and the media
    /// colour tag (#782) offers it as a picker.
    ///
    /// The names are not decoration. A colour tag with no name is unusable
    /// without colour vision, so every entry has to be nameable for the menu
    /// label and the row's VoiceOver announcement. `LocalizedStringResource`
    /// (not `String`) so the names go through the String Catalog like the rest
    /// of the user-facing text.
    static let namedDefaultPalette: [(hex: String, name: LocalizedStringResource)] = [
        ("#FF6B6B", "Red"),
        ("#FFA94D", "Orange"),
        ("#FFD93D", "Yellow"),
        ("#6BCB77", "Green"),
        ("#4ECDC4", "Teal"),
        ("#4D96FF", "Blue"),
        ("#9D7EE0", "Purple"),
        ("#FF6FB5", "Pink")
    ]

    /// Default palette cycled when the user adds a new Type via the Manage Types sheet.
    /// Mirrors the 8 named colors from the pre-PR-55 cue row palette so we keep visual
    /// continuity with the MVP era.
    static let defaultPalette: [String] = namedDefaultPalette.map(\.hex)

    /// The palette name for a stored hex, or `nil` when the hex is not one of
    /// the eight — which a hand-edited `.cuelist` can produce. Callers must
    /// degrade rather than invent a name.
    static func paletteName(forHex hex: String) -> LocalizedStringResource? {
        namedDefaultPalette.first { $0.hex == hex }?.name
    }
}
