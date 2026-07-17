import Foundation

/// What a single output channel of the chosen audio device carries.
///
/// `ltc` / `trackLeft` / `trackRight` are *unique* roles — at most one channel
/// may hold each (assigning one clears any other channel that had it). `silent`
/// is the fill role and may repeat.
enum ChannelRole: String, Codable, CaseIterable, Sendable {
    case silent
    case ltc
    case trackLeft
    case trackRight

    /// Roles that may appear on at most one channel at a time.
    static let uniqueRoles: [Self] = [.ltc, .trackLeft, .trackRight]

    var isUnique: Bool { Self.uniqueRoles.contains(self) }

    var displayName: String {
        switch self {
        case .silent: "Silent"
        case .ltc: "LTC"
        case .trackLeft: "Track L"
        case .trackRight: "Track R"
        }
    }
}

/// The user's LTC output routing: which audio device, and what each of its
/// output channels carries. Persisted as JSON in `UserDefaults` (a machine /
/// session preference, not part of the `.cuelist` document) by `LTCRoutingStore`.
///
/// `channelRoles` is indexed by output-channel number (0-based). It is kept in
/// sync with the chosen device's channel count via `resized(toChannelCount:)`;
/// out-of-range lookups read as `.silent`.
struct LTCRoutingSettings: Codable, Equatable, Sendable {

    /// Master switch for LTC output. When `false` the LTC engine never runs and
    /// the channel assignments below are dormant. Defaults to `false` — a fresh
    /// install emits no timecode until the user opts in.
    var isEnabled: Bool

    /// Core Audio device UID of the selected output, or `nil` to follow the
    /// system default output device.
    var deviceUID: String?

    /// Role per output channel, indexed 0-based.
    var channelRoles: [ChannelRole]

    /// Digital amplitude of the generated LTC signal, 0...1 (#651). Scales only
    /// the LTC samples, independent of the program (track) audio level. Cannot
    /// exceed the system output volume.
    var amplitude: Float

    /// LTC output level for a fresh install — near full-scale for reliable
    /// decoding, with a little headroom (raised from the old hard-coded 0.8).
    static let defaultAmplitude: Float = 0.9

    static let `default` = Self(isEnabled: false, deviceUID: nil, channelRoles: [])

    init(
        isEnabled: Bool = false,
        deviceUID: String?,
        channelRoles: [ChannelRole],
        amplitude: Float = defaultAmplitude
    ) {
        self.isEnabled = isEnabled
        self.deviceUID = deviceUID
        self.channelRoles = channelRoles
        self.amplitude = Self.clampAmplitude(amplitude)
    }

    private static func clampAmplitude(_ value: Float) -> Float {
        min(max(value, 0), 1)
    }

    // MARK: Codable — tolerate payloads written before `isEnabled` existed.

    private enum CodingKeys: String, CodingKey { case isEnabled, deviceUID, channelRoles, amplitude }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        deviceUID = try container.decodeIfPresent(String.self, forKey: .deviceUID)
        channelRoles = try container.decodeIfPresent([ChannelRole].self, forKey: .channelRoles) ?? []
        let storedAmplitude = try container.decodeIfPresent(Float.self, forKey: .amplitude) ?? Self.defaultAmplitude
        amplitude = Self.clampAmplitude(storedAmplitude)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encodeIfPresent(deviceUID, forKey: .deviceUID)
        try container.encode(channelRoles, forKey: .channelRoles)
        try container.encode(amplitude, forKey: .amplitude)
    }

    // MARK: Queries

    func role(forChannel index: Int) -> ChannelRole {
        channelRoles.indices.contains(index) ? channelRoles[index] : .silent
    }

    /// The channel carrying `role`, if any (first match — unique roles only ever
    /// have one).
    func channel(for role: ChannelRole) -> Int? {
        channelRoles.firstIndex(of: role)
    }

    var ltcChannel: Int? { channel(for: .ltc) }

    /// The channel carrying the left / right legs of the program (track) audio,
    /// if assigned. Track channels are optional — a 1-channel "LTC only" cable is
    /// valid; without them the program audio is silent while LTC runs.
    var trackLeftChannel: Int? { channel(for: .trackLeft) }
    var trackRightChannel: Int? { channel(for: .trackRight) }

    /// Whether any channel carries program (track) audio.
    var hasTrackChannels: Bool { trackLeftChannel != nil || trackRightChannel != nil }

    /// Routing is usable once LTC is enabled and an LTC output channel has been
    /// assigned. (Track channels are optional — a 1-channel "LTC only" cable is
    /// valid.)
    var isComplete: Bool { isEnabled && ltcChannel != nil }

    // MARK: Transforms (value-returning — callers persist the result)

    /// Assign `role` to `channel`. If `role` is unique, any other channel that
    /// held it is reset to `.silent` first. Out-of-range channels are ignored.
    func assigning(_ role: ChannelRole, toChannel channel: Int) -> Self {
        guard channelRoles.indices.contains(channel) else { return self }
        var roles = channelRoles
        if role.isUnique {
            for index in roles.indices where roles[index] == role {
                roles[index] = .silent
            }
        }
        roles[channel] = role
        return Self(isEnabled: isEnabled, deviceUID: deviceUID, channelRoles: roles, amplitude: amplitude)
    }

    /// Toggle the master switch, leaving the device + channel layout untouched.
    func settingEnabled(_ enabled: Bool) -> Self {
        Self(isEnabled: enabled, deviceUID: deviceUID, channelRoles: channelRoles, amplitude: amplitude)
    }

    /// Set the LTC output level (#651), clamped to 0...1. Callers persist the
    /// result. Only scales the LTC signal; program audio is untouched.
    func settingAmplitude(_ value: Float) -> Self {
        Self(isEnabled: isEnabled, deviceUID: deviceUID, channelRoles: channelRoles, amplitude: value)
    }

    /// Select a different output device. The channel-role list is left as-is;
    /// pair this with `resized(toChannelCount:)` once the new device's channel
    /// count is known.
    func selectingDevice(uid: String?) -> Self {
        Self(isEnabled: isEnabled, deviceUID: uid, channelRoles: channelRoles, amplitude: amplitude)
    }

    /// Pad with `.silent` or truncate so `channelRoles.count == count`. If the
    /// list was empty (or fewer LTC/Track roles survive the resize than fit),
    /// the default layout is *not* re-applied here — use `withDefaultRoles(...)`
    /// for that.
    func resized(toChannelCount count: Int) -> Self {
        let clamped = max(0, count)
        var roles = channelRoles
        if roles.count > clamped {
            roles = Array(roles.prefix(clamped))
        } else if roles.count < clamped {
            roles.append(contentsOf: repeatElement(.silent, count: clamped - roles.count))
        }
        return Self(isEnabled: isEnabled, deviceUID: deviceUID, channelRoles: roles, amplitude: amplitude)
    }

    /// Replace the channel layout with the default one for `count` channels.
    func withDefaultRoles(forChannelCount count: Int) -> Self {
        Self(isEnabled: isEnabled, deviceUID: deviceUID, channelRoles: Self.defaultRoles(forChannelCount: count), amplitude: amplitude)
    }

    /// Default channel layout: ch 0 = LTC, ch 1 = Track L, ch 2 = Track R, the
    /// rest silent (matching the epic-#33 Gherkin's "channel 1 LTC, channels 2/3
    /// Track L/R" on a 4-channel interface). Fewer channels → as many of that
    /// prefix as fit.
    static func defaultRoles(forChannelCount count: Int) -> [ChannelRole] {
        let preferred: [ChannelRole] = [.ltc, .trackLeft, .trackRight]
        let clamped = max(0, count)
        return (0..<clamped).map { index in
            index < preferred.count ? preferred[index] : .silent
        }
    }
}
