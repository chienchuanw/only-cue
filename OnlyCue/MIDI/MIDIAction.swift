import Foundation

/// A continuous parameter a fader/knob (CC value 0…127, absolute) can drive.
enum ContinuousTarget: String, Codable, CaseIterable, Sendable {
    case scrub          // playhead position across the track
    case playbackRate   // rehearsal speed
    case ltcLevel       // LTC output amplitude

    var displayName: String {
        switch self {
        case .scrub: "Scrub Playhead"
        case .playbackRate: "Playback Rate"
        case .ltcLevel: "LTC Output Level"
        }
    }
}

/// What a MIDI control is bound to: either a discrete `KeymapAction` (fired on a
/// press edge) or a continuous `ContinuousTarget` (driven by a fader's value).
///
/// Encodes as a single **stable token string** (`"discrete:playPause"`,
/// `"continuous:scrub"`) so a `MIDIMap` persists as a flat `[token: token]` JSON
/// object — diffable and migration-friendly. Mirrors the token discipline of
/// `KeymapAction.rawValue`.
enum MIDIAction: Equatable, Codable, Sendable {
    case discrete(KeymapAction)
    case continuous(ContinuousTarget)

    var isContinuous: Bool { if case .continuous = self { return true } else { return false } }

    var displayName: String {
        switch self {
        case .discrete(let action): action.displayName
        case .continuous(let target): target.displayName
        }
    }

    var token: String {
        switch self {
        case .discrete(let action): "discrete:\(action.rawValue)"
        case .continuous(let target): "continuous:\(target.rawValue)"
        }
    }

    init?(token: String) {
        guard let separator = token.firstIndex(of: ":") else { return nil }
        let tag = String(token[..<separator])
        let value = String(token[token.index(after: separator)...])
        switch tag {
        case "discrete":
            guard let action = KeymapAction(rawValue: value) else { return nil }
            self = .discrete(action)
        case "continuous":
            guard let target = ContinuousTarget(rawValue: value) else { return nil }
            self = .continuous(target)
        default:
            return nil
        }
    }

    // Codable: a single token string (not a keyed container).
    init(from decoder: Decoder) throws {
        let token = try decoder.singleValueContainer().decode(String.self)
        guard let action = Self(token: token) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "Unknown MIDIAction token \(token)"))
        }
        self = action
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(token)
    }
}
