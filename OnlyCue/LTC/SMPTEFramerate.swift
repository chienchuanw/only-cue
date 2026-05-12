import Foundation

/// The SMPTE timecode rates OnlyCue's LTC generator supports (epic #33).
/// `23.976` / `29.97` / `59.94` and pulldown are out of scope for v1.
/// The `rawValue` is the stable on-disk token used when the project framerate
/// is persisted in `.cuelist` (a later leaf) — don't change one without a
/// migration.
enum SMPTEFramerate: String, Codable, CaseIterable, Identifiable, Sendable {
    case fps24 = "24"
    case fps25 = "25"
    case fps30 = "30"
    case fps30drop = "30df"

    var id: String { rawValue }

    /// Frames per second, nominal. For `fps30drop` the *physical* rate in real
    /// broadcast hardware is 29.97; v1 treats it as a 30 fps timeline whose
    /// timecode *labels* follow the drop-frame counting rule (see `Timecode`),
    /// which is the simplification the epic asks for (29.97 itself is excluded).
    var framesPerSecond: Int {
        switch self {
        case .fps24: return 24
        case .fps25: return 25
        case .fps30, .fps30drop: return 30
        }
    }

    var isDropFrame: Bool { self == .fps30drop }

    var displayName: String {
        switch self {
        case .fps24: return "24 fps"
        case .fps25: return "25 fps"
        case .fps30: return "30 fps (non-drop)"
        case .fps30drop: return "30 fps (drop-frame)"
        }
    }
}
