import Foundation

/// Which audio channel of a media file carries LTC, as the user declared it
/// (#793). Authored data, kept separate from `MediaItem.rememberedLTC`,
/// which is derived: conflating them would let Clear erase what the user said.
///
/// Naming a channel is also the escape hatch from the 60 s scan ceiling. A
/// file whose LTC begins at 90 s is invisible to `.auto`, but a named channel
/// sends the full-file pass at it, which finds it.
/// `Hashable` is load-bearing, not decoration: SwiftUI's `.tag()` requires
/// it, and the channel picker in the edit sheet tags rows with these values.
enum LTCChannelSelection: Hashable, Sendable {

    /// Run the windowed scan across every channel and take the first that
    /// corroborates. The default.
    case auto

    /// The user named this channel: skip the scan, decode this one across
    /// the whole file. Zero-based, as `StripedTimecodeTrack.ltcChannel` is.
    case channel(Int)

    /// The user asserts this file carries no LTC: decode nothing.
    case none
}

/// Encoded as a flat string rather than by Swift's synthesised form for
/// enums with associated values, which would write `{"channel":{"_0":2}}`
/// — a compiler-generated key inside a persisted document format is a trap
/// for the next schema change.
extension LTCChannelSelection: Codable {

    private static let channelPrefix = "channel:"

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "none":
            self = .none
        case let value where value.hasPrefix(Self.channelPrefix):
            let index = Int(value.dropFirst(Self.channelPrefix.count))
            // An unparseable or negative index falls back to auto rather
            // than failing the load: one malformed field must not make a
            // whole show file unopenable.
            self = index.map { $0 >= 0 ? .channel($0) : .auto } ?? .auto
        default:
            self = .auto
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .auto: try container.encode("auto")
        case .none: try container.encode("none")
        case .channel(let index): try container.encode("\(Self.channelPrefix)\(index)")
        }
    }
}
