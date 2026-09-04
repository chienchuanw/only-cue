import Foundation

/// Encodes MIDI 1.0 messages as Universal MIDI Packet words, for
/// `MIDISendEventList` (epic #794).
///
/// `MIDISend` and `MIDIPacketList` — which take raw MIDI 1.0 bytes directly —
/// were deprecated in macOS 11, and the Release configuration treats warnings as
/// errors, so the send path has to speak UMP. This type is where that translation
/// lives: pure, hardware-free and unit-tested, so `MTCOutput` stays a thin edge
/// that only opens a port and hands over words.
///
/// It is the write-side counterpart of the UMP *parsing* `MIDIInput` already does
/// in `messages(in:)`, and follows the same spec tables.
enum MIDIUniversalPacket {

    /// UMP message type for System Real Time and System Common messages.
    private static let systemMessageType: UInt32 = 0x1
    /// UMP message type for 7-bit SysEx data messages.
    private static let sysEx7MessageType: UInt32 = 0x3
    /// Data bytes carried by one SysEx7 packet.
    static let sysEx7BytesPerPacket = 6

    /// SysEx7 packet status nibble.
    private enum SysEx7Status: UInt32 {
        case complete = 0x0
        case start = 0x1
        case `continue` = 0x2
        case end = 0x3
    }

    // MARK: - System Common

    /// One System Common message (e.g. a `0xF1` quarter-frame) as a single UMP
    /// word: `[type|group][status][data1][data2]`.
    ///
    /// Messages shorter than three bytes pass `0` for the unused data bytes,
    /// which is what the spec requires.
    static func systemCommonWord(status: UInt8, data1: UInt8, data2: UInt8, group: UInt8 = 0) -> UInt32 {
        (systemMessageType << 28)
            | (UInt32(group & 0x0F) << 24)
            | (UInt32(status) << 16)
            | (UInt32(data1) << 8)
            | UInt32(data2)
    }

    // MARK: - SysEx7

    /// A SysEx payload as UMP SysEx7 packets, two words each.
    ///
    /// `payload` is the message *content*: any leading `0xF0` and trailing `0xF7`
    /// are stripped, because the framing belongs to the byte stream rather than
    /// to UMP, where the packet status nibble carries it instead. Payloads of six
    /// bytes or fewer become a single `complete` packet; longer ones become
    /// `start` / `continue…` / `end`.
    static func sysEx7Words(payload: [UInt8], group: UInt8 = 0) -> [UInt32] {
        let content = stripFraming(payload)
        guard !content.isEmpty else { return [] }

        let chunks = stride(from: 0, to: content.count, by: sysEx7BytesPerPacket).map {
            Array(content[$0..<min($0 + sysEx7BytesPerPacket, content.count)])
        }

        return chunks.enumerated().flatMap { index, chunk -> [UInt32] in
            let status: SysEx7Status
            switch (chunks.count, index) {
            case (1, _):                 status = .complete
            case (_, 0):                 status = .start
            case (_, chunks.count - 1):  status = .end
            default:                     status = .continue
            }
            return packetWords(chunk: chunk, status: status, group: group)
        }
    }

    /// The two words of one SysEx7 packet: a header word carrying the status and
    /// byte count plus the first two data bytes, then the remaining four.
    private static func packetWords(chunk: [UInt8], status: SysEx7Status, group: UInt8) -> [UInt32] {
        func byte(_ index: Int) -> UInt32 { index < chunk.count ? UInt32(chunk[index] & 0x7F) : 0 }

        let first = (sysEx7MessageType << 28)
            | (UInt32(group & 0x0F) << 24)
            | (status.rawValue << 20)
            | (UInt32(chunk.count) << 16)
            | (byte(0) << 8)
            | byte(1)
        let second = (byte(2) << 24) | (byte(3) << 16) | (byte(4) << 8) | byte(5)
        return [first, second]
    }

    /// Drop a leading `0xF0` and a trailing `0xF7` if present.
    private static func stripFraming(_ payload: [UInt8]) -> [UInt8] {
        var content = payload[...]
        if content.first == 0xF0 { content = content.dropFirst() }
        if content.last == 0xF7 { content = content.dropLast() }
        return Array(content)
    }
}
