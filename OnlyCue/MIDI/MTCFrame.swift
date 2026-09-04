import Foundation

/// The MIDI Timecode wire format — pure byte encoding, no CoreMIDI (epic #794).
///
/// Two message shapes carry MTC:
///
/// - **Quarter-frame** (`F1 <data>`) — the running stream. Each message carries
///   one nibble of the timecode, so a complete value takes **eight** messages
///   and therefore spans **two** frames. Emitted continuously while the
///   transport runs.
/// - **Full Frame** (`F0 7F 7F 01 01 hh mm ss ff F7`) — a Universal Real Time
///   SysEx that jams a receiver to an absolute position in one message. Sent on
///   locate (play-start, seek, and scrubbing while paused) so a console does not
///   have to wait two frames to know where it is.
///
/// Mirrors `MIDIMessage` in spirit: pure, hardware-free, and the place where all
/// the bit-twiddling is pinned by tests. `MTCOutput` only pushes these bytes at
/// the right times.
///
/// **Rate bits are two bits wide** — MTC encodes exactly 24 / 25 / 29.97-DF / 30
/// and has no 30-fps-drop-frame code. `SMPTEFramerate.fps30drop` therefore takes
/// the 29.97-DF slot while still being clocked at 30 fps, which is the same
/// simplification `LTCEncoder` already ships (ADR-019, reaffirmed by ADR-032).
/// The invariant that matters is that LTC and MTC never disagree.
enum MTCFrame {

    /// Status byte introducing a quarter-frame message.
    static let quarterFrameStatus: UInt8 = 0xF1

    /// Quarter-frame messages needed to transmit one complete timecode value.
    static let piecesPerTimecode = 8

    /// Frames spanned by one full eight-message quarter-frame sequence.
    static let framesPerSequence = 2

    // MARK: - Rate bits

    /// The two-bit MTC rate code for `rate`.
    static func rateBits(for rate: SMPTEFramerate) -> UInt8 {
        switch rate {
        case .fps24:     return 0b00
        case .fps25:     return 0b01
        case .fps30drop: return 0b10   // 29.97 drop — the only drop-frame slot MTC has
        case .fps30:     return 0b11
        }
    }

    // MARK: - Quarter frames

    /// The data byte for quarter-frame `piece` (0...7) of `timecode`.
    ///
    /// Layout is `0nnn dddd`: `nnn` is the piece index, `dddd` the payload
    /// nibble. Pieces run least-significant-first — frames, then seconds, then
    /// minutes, then hours — with the rate bits riding in piece 7 alongside the
    /// single high bit of the hour.
    ///
    /// `piece` is clamped to 0...7: an out-of-range index is a caller bug, and
    /// clamping keeps a malformed byte (one whose high nibble names a different
    /// piece) off the wire.
    static func quarterFrameByte(piece: Int, timecode: Timecode) -> UInt8 {
        let index = min(max(piece, 0), piecesPerTimecode - 1)
        let payload: UInt8
        switch index {
        case 0: payload = UInt8(timecode.frames) & 0x0F
        case 1: payload = (UInt8(timecode.frames) >> 4) & 0x01
        case 2: payload = UInt8(timecode.seconds) & 0x0F
        case 3: payload = (UInt8(timecode.seconds) >> 4) & 0x03
        case 4: payload = UInt8(timecode.minutes) & 0x0F
        case 5: payload = (UInt8(timecode.minutes) >> 4) & 0x03
        case 6: payload = UInt8(timecode.hours) & 0x0F
        default: payload = (rateBits(for: timecode.rate) << 1) | ((UInt8(timecode.hours) >> 4) & 0x01)
        }
        return (UInt8(index) << 4) | payload
    }

    /// The complete two-byte quarter-frame message for `piece` of `timecode`.
    static func quarterFrameMessage(piece: Int, timecode: Timecode) -> [UInt8] {
        [quarterFrameStatus, quarterFrameByte(piece: piece, timecode: timecode)]
    }

    // MARK: - Full Frame

    /// The Universal Real Time SysEx that locates a receiver to `timecode`.
    ///
    /// `F0 7F <device> 01 01 hh mm ss ff F7`, addressed to `0x7F` (all devices).
    /// The hour byte packs the rate bits above the hour: `(rateBits << 5) | hh`.
    static func fullFrameBytes(_ timecode: Timecode) -> [UInt8] {
        let hourByte = (rateBits(for: timecode.rate) << 5) | (UInt8(timecode.hours) & 0x1F)
        return [
            0xF0, 0x7F, 0x7F,   // SysEx start, Universal Real Time, all devices
            0x01, 0x01,         // sub-ID 1: MIDI Time Code — sub-ID 2: Full Message
            hourByte,
            UInt8(timecode.minutes),
            UInt8(timecode.seconds),
            UInt8(timecode.frames),
            0xF7                // SysEx end
        ]
    }
}
