import Foundation

enum TimeFormat {
    /// Formats `seconds` as `HH:MM:SS.mmm`.
    /// Negative values clamp to zero. Sub-millisecond values round half-away-from-zero.
    static func hms(_ seconds: TimeInterval) -> String {
        let clamped = max(0, seconds)
        let totalMillis = Int((clamped * 1000).rounded(.toNearestOrAwayFromZero))
        let hours = totalMillis / 3_600_000
        let minutes = (totalMillis % 3_600_000) / 60_000
        let secs = (totalMillis % 60_000) / 1000
        let millis = totalMillis % 1000
        return String(format: "%02d:%02d:%02d.%03d", hours, minutes, secs, millis)
    }
}
