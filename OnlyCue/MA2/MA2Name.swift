import Foundation

/// Sanitizes a clip name into a grandMA2-safe sequence name (#686): ASCII
/// printable only (MA names are effectively ASCII), embedded double quotes
/// stripped, whitespace runs collapsed. Falls back to `OnlyCue <slot>` when
/// nothing usable survives (e.g. an all-CJK name).
enum MA2Name {
    static func sanitize(_ raw: String, fallbackSlot: Int) -> String {
        let asciiPrintable = raw.unicodeScalars
            .filter { $0.isASCII && $0.value >= 0x20 && $0.value != 0x22 }  // 0x22 = "
            .map(Character.init)
        let collapsed = String(asciiPrintable)
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .joined(separator: " ")
        return collapsed.isEmpty ? "OnlyCue \(fallbackSlot)" : collapsed
    }
}
