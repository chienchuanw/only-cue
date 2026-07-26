import Foundation

/// Identity of one physical control on a MIDI surface — the key of `MIDIMap`.
/// A control is `(channel, kind, number)`; its value (velocity / CC value) is
/// deliberately excluded so the same knob is one identity regardless of position.
///
/// `token` is the **stable on-disk string** (`"cc:1:45"`, `"note:1:60"`) used as
/// the JSON key in the persisted map — never change its shape without a migration.
struct MIDIControlID: Hashable, Codable, Sendable {
    enum Kind: String, Codable, Sendable { case note, cc }

    let channel: UInt8   // 1…16
    let kind: Kind
    let number: UInt8    // 0…127

    init(channel: UInt8, kind: Kind, number: UInt8) {
        self.channel = channel
        self.kind = kind
        self.number = number
    }

    init?(message: MIDIMessage) {
        switch message {
        case let .note(channel, number, _):
            self.init(channel: channel, kind: .note, number: number)
        case let .controlChange(channel, number, _):
            self.init(channel: channel, kind: .cc, number: number)
        }
    }

    var token: String { "\(kind.rawValue):\(channel):\(number)" }

    init?(token: String) {
        let parts = token.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let kind = Kind(rawValue: String(parts[0])),
              let channel = UInt8(parts[1]),
              let number = UInt8(parts[2])
        else { return nil }
        self.init(channel: channel, kind: kind, number: number)
    }
}
