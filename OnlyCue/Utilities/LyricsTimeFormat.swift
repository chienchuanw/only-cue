import Foundation

/// Parses and formats media-relative time values for the Lyrics Editor's line
/// timestamps and offset field. Unlike `TimeFormat`, this is plain decimal
/// seconds (`M:SS.mmm`), not SMPTE — lyrics never carry frames.
enum LyricsTimeFormat {

    /// Formats `seconds` as `M:SS.mmm`, or `H:MM:SS.mmm` once past an hour.
    /// Negative input clamps to zero.
    static func string(_ seconds: TimeInterval) -> String {
        let total = max(0, seconds)
        let whole = Int(total)
        let millis = Int((total - Double(whole)) * 1000.0 + 0.5)
        let hours = whole / 3600
        let minutes = (whole % 3600) / 60
        let secs = whole % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d.%03d", hours, minutes, secs, millis)
        }
        return String(format: "%d:%02d.%03d", minutes, secs, millis)
    }

    /// Parses `"S"`, `"M:SS"`, or `"H:MM:SS"` with an optional `.mmm` fraction
    /// on the final component. Returns `nil` for empty input, non-numeric
    /// components, negative values, more than three components, or a
    /// minutes/seconds component outside `0...59`.
    static func parse(_ text: String) -> TimeInterval? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }

        var values: [Double] = []
        for part in parts {
            guard let value = Double(part), value >= 0, value.isFinite else { return nil }
            values.append(value)
        }
        // Every component except the last must be a whole number in 0...59.
        for value in values.dropLast() {
            guard value == value.rounded(), value <= 59 else { return nil }
        }
        // The seconds component of a multi-part value must be < 60.
        if values.count > 1, let last = values.last, last >= 60 { return nil }

        switch values.count {
        case 1: return values[0]
        case 2: return values[0] * 60 + values[1]
        default: return values[0] * 3600 + values[1] * 60 + values[2]
        }
    }
}
