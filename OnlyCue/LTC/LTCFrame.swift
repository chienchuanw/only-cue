import Foundation

/// One 80-bit SMPTE LTC frame (SMPTE 12M) as the bit sequence in *transmission
/// order* — `bits[0]` is the first bit on the wire, and within each multi-bit
/// field the low-order bit comes first (LTC is LSB-first).
///
/// Built from a `Timecode`. The eight 4-bit user-bit ("binary group") fields
/// and the colour-frame and binary-group-flag bits are zero; the drop-frame
/// flag (bit 10) follows the timecode's rate. The bit-polarity-correction
/// (parity) bit is set so the 80-bit word has an even number of 1s — v1 places
/// it at bit 27 (the 24 / 30 fps convention) for *all* rates; the 25 fps
/// standard moves it to bit 59, which a follow-up can add if a 25 fps reader
/// needs it. The 16-bit sync word `0011 1111 1111 1101` occupies bits 64–79.
struct LTCFrame: Equatable, Sendable {

    /// Fixed sync word, bits 64–79, transmission order: `00` · twelve `1`s · `01`.
    static let syncWord: [Bool] = [false, false] + Array(repeating: true, count: 12) + [false, true]

    /// Bit 27 — the bit-polarity-correction (parity) position used by `LTCFrame`.
    static let parityBitIndex = 27

    /// Exactly 80 bits, transmission order.
    let bits: [Bool]

    /// Wrap a raw 80-bit transmission-order word (e.g. recovered by a decoder).
    init(bits: [Bool]) {
        precondition(bits.count == 80, "an LTC frame is exactly 80 bits")
        self.bits = bits
    }

    init(timecode: Timecode) {
        var word = [Bool](repeating: false, count: 80)

        func writeBCD(_ value: Int, unitsAt: Int, unitsBits: Int, tensAt: Int, tensBits: Int) {
            let units = value % 10
            let tens = value / 10
            for offset in 0..<unitsBits { word[unitsAt + offset] = (units >> offset) & 1 == 1 }
            for offset in 0..<tensBits { word[tensAt + offset] = (tens >> offset) & 1 == 1 }
        }

        writeBCD(timecode.frames, unitsAt: 0, unitsBits: 4, tensAt: 8, tensBits: 2)
        word[10] = timecode.rate.isDropFrame
        writeBCD(timecode.seconds, unitsAt: 16, unitsBits: 4, tensAt: 24, tensBits: 3)
        writeBCD(timecode.minutes, unitsAt: 32, unitsBits: 4, tensAt: 40, tensBits: 3)
        writeBCD(timecode.hours, unitsAt: 48, unitsBits: 4, tensAt: 56, tensBits: 2)
        for (offset, bit) in Self.syncWord.enumerated() { word[64 + offset] = bit }

        if word.lazy.filter({ $0 }).count.isMultiple(of: 2) == false {
            word[Self.parityBitIndex] = true
        }
        self.bits = word
    }

    // MARK: - Decoded fields (for round-trip checks)

    var frames: Int { value(at: 0, bits: 4) + value(at: 8, bits: 2) * 10 }
    var seconds: Int { value(at: 16, bits: 4) + value(at: 24, bits: 3) * 10 }
    var minutes: Int { value(at: 32, bits: 4) + value(at: 40, bits: 3) * 10 }
    var hours: Int { value(at: 48, bits: 4) + value(at: 56, bits: 2) * 10 }
    var isDropFrame: Bool { bits[10] }
    var hasEvenParity: Bool { bits.lazy.filter { $0 }.count.isMultiple(of: 2) }
    var syncWordIsValid: Bool { Array(bits[64..<80]) == Self.syncWord }

    /// `true` when the sync word is intact and the word has even parity — the
    /// two integrity checks a decoder applies before trusting the fields.
    var isWellFormed: Bool { syncWordIsValid && hasEvenParity }

    /// The timecode this frame carries, at `framesPerSecond` (the wire form only
    /// distinguishes drop-frame via bit 10 — the rate magnitude comes from the
    /// signal's measured bit period). `nil` if the BCD fields are out of range
    /// (or a drop-frame-skipped number), or if `framesPerSecond` has no
    /// `SMPTEFramerate`.
    func timecode(framesPerSecond: Int) -> Timecode? {
        guard let rate = SMPTEFramerate.matching(framesPerSecond: framesPerSecond, isDropFrame: isDropFrame) else {
            return nil
        }
        return Timecode(hours: hours, minutes: minutes, seconds: seconds, frames: frames, rate: rate)
    }

    private func value(at start: Int, bits count: Int) -> Int {
        (0..<count).reduce(0) { $0 | (bits[start + $1] ? (1 << $1) : 0) }
    }
}
