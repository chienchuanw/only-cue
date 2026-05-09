import Foundation

/// Customisable appearance settings for `NotesOverlayView`. Persisted to
/// `UserDefaults` via `@AppStorage("notesOverlayPreferences")` as a JSON-
/// encoded `Data` blob — single key, single source of truth, single
/// "Restore Defaults" button on the appearance sheet.
///
/// Defaults reproduce the visual the overlay shipped with in PR #72:
/// bottom-aligned, `.title` font scale (1.0), white text, `.ultraThinMaterial`
/// background (represented here as `nil` `backgroundColorHex`), no cue-ID prefix.
struct NotesOverlayPreferences: Codable, Equatable {

    enum Position: String, Codable, CaseIterable {
        case top
        case center
        case bottom
    }

    static let fontScaleRange: ClosedRange<Double> = 0.75...3.0

    var position: Position
    var fontScale: Double
    var textColorHex: String
    var backgroundColorHex: String?
    var showCueIDPrefix: Bool

    static let `default` = Self(
        position: .bottom,
        fontScale: 1.0,
        textColorHex: "#FFFFFF",
        backgroundColorHex: nil,
        showCueIDPrefix: false
    )

    init(
        position: Position,
        fontScale: Double,
        textColorHex: String,
        backgroundColorHex: String?,
        showCueIDPrefix: Bool
    ) {
        self.position = position
        self.fontScale = Self.clamp(fontScale)
        self.textColorHex = textColorHex
        self.backgroundColorHex = backgroundColorHex
        self.showCueIDPrefix = showCueIDPrefix
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        position = try container.decode(Position.self, forKey: .position)
        fontScale = Self.clamp(try container.decode(Double.self, forKey: .fontScale))
        textColorHex = try container.decode(String.self, forKey: .textColorHex)
        backgroundColorHex = try container.decodeIfPresent(String.self, forKey: .backgroundColorHex)
        showCueIDPrefix = try container.decode(Bool.self, forKey: .showCueIDPrefix)
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, fontScaleRange.lowerBound), fontScaleRange.upperBound)
    }

    static let storageKey = "notesOverlayPreferences"

    /// Encoded `default` for use as `@AppStorage` initial value. Computed once.
    static let defaultEncoded: Data = {
        (try? JSONEncoder().encode(Self.default)) ?? Data()
    }()

    var encoded: Data {
        (try? JSONEncoder().encode(self)) ?? Self.defaultEncoded
    }

    /// Decode prefs from `@AppStorage` data; falls back to `.default` on failure
    /// (corrupt data, schema drift) so the UI always has something sensible.
    static func decode(_ data: Data) -> Self {
        (try? JSONDecoder().decode(Self.self, from: data)) ?? .default
    }
}

extension Notification.Name {
    static let editNotesOverlayAppearance = Notification.Name("OnlyCue.editNotesOverlayAppearance")
}
