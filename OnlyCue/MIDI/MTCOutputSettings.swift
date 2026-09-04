import Foundation

/// The user's MTC output configuration: whether to send MIDI Timecode, and to
/// which CoreMIDI destination. Persisted as JSON in `UserDefaults` (a machine /
/// session preference, not part of the `.cuelist` document) by `MTCOutputStore`.
///
/// Deliberately independent of `LTCRoutingSettings` — MTC and LTC can each run
/// alone, together, or not at all. It carries no channel-role layer because a
/// MIDI destination has no channels to assign; the destination *is* the routing.
///
/// v1 holds a single destination. Fanning one MTC stream out to several
/// destinations is the analogue of LTC's #655 multi-channel work and is
/// deliberately deferred.
struct MTCOutputSettings: Codable, Equatable, Sendable {

    /// Master switch for MTC output. When `false` the generator never runs and
    /// `destinationUID` lies dormant. Defaults to `false` — a fresh install
    /// emits no timecode until the user opts in, matching LTC.
    var isEnabled: Bool

    /// `kMIDIPropertyUniqueID` of the chosen destination, or `nil` when none has
    /// been picked. Unlike LTC's `deviceUID`, `nil` is *not* "follow the default"
    /// — CoreMIDI has no default destination, so `nil` simply means unconfigured.
    var destinationUID: String?

    static let `default` = Self(isEnabled: false, destinationUID: nil)

    init(isEnabled: Bool = false, destinationUID: String?) {
        self.isEnabled = isEnabled
        self.destinationUID = destinationUID
    }

    /// Usable once MTC is enabled *and* a destination has been chosen.
    var isComplete: Bool { isEnabled && destinationUID != nil }

    // MARK: Transforms (value-returning — callers persist the result)

    /// Toggle the master switch, leaving the chosen destination untouched.
    func settingEnabled(_ enabled: Bool) -> Self {
        Self(isEnabled: enabled, destinationUID: destinationUID)
    }

    /// Select a different destination, leaving the master switch untouched.
    func selectingDestination(uid: String?) -> Self {
        Self(isEnabled: isEnabled, destinationUID: uid)
    }

    // MARK: Codable — tolerate payloads written before a key existed.

    private enum CodingKeys: String, CodingKey { case isEnabled, destinationUID }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        destinationUID = try container.decodeIfPresent(String.self, forKey: .destinationUID)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encodeIfPresent(destinationUID, forKey: .destinationUID)
    }
}
