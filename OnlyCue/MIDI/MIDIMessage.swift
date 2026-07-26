import Foundation

/// A MIDI message OnlyCue acts on. v1 recognises Note and Control Change only;
/// every other status byte parses to `nil`. Channel is stored 1-based (1…16).
///
/// Pure and hardware-free — the mapping from raw bytes is pinned by
/// `MIDIMessageTests`; the live CoreMIDI edge (`MIDIInputHost`) only feeds bytes
/// in. Mirrors `OSCCommand` / `OSCMessage`.
enum MIDIMessage: Equatable, Sendable {
    case note(channel: UInt8, number: UInt8, velocity: UInt8)
    case controlChange(channel: UInt8, number: UInt8, value: UInt8)

    static func parse(_ bytes: [UInt8]) -> Self? {
        guard let status = bytes.first, status >= 0x80 else { return nil }
        let kind = status & 0xF0
        let channel = (status & 0x0F) + 1   // 1-based
        switch kind {
        case 0x90:                          // Note On
            guard bytes.count >= 3 else { return nil }
            return .note(channel: channel, number: bytes[1], velocity: bytes[2])
        case 0x80:                          // Note Off → zero-velocity note
            guard bytes.count >= 3 else { return nil }
            return .note(channel: channel, number: bytes[1], velocity: 0)
        case 0xB0:                          // Control Change
            guard bytes.count >= 3 else { return nil }
            return .controlChange(channel: channel, number: bytes[1], value: bytes[2])
        default:
            return nil
        }
    }
}
