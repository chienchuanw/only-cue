import Foundation

enum TimeFormat {
    /// Formats `seconds` as SMPTE timecode `HH:MM:SS:FF` (`HH:MM:SS;FF` for
    /// drop-frame) at the given `rate`. Negative values clamp to zero; sub-frame
    /// values round half-away-from-zero (inherited from `Timecode`).
    static func smpte(_ seconds: TimeInterval, rate: SMPTEFramerate) -> String {
        Timecode(totalSeconds: max(0, seconds), rate: rate).displayString
    }

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

    /// Compact countdown format for trend/anticipation displays:
    /// - Sub-minute: `"5.2"` (seconds with one decimal place).
    /// - Sub-hour: `"1:23.5"`.
    /// - Hour-or-more: `"1:23:45.6"`.
    /// Decisecond precision is intentional — coarser than `hms`'s ms because
    /// countdowns are glanceable trend displays where sub-100ms is visual noise.
    /// Negative values clamp to zero.
    static func compactCountdown(_ seconds: TimeInterval) -> String {
        let clamped = max(0, seconds)
        let totalDeciseconds = Int((clamped * 10).rounded(.toNearestOrAwayFromZero))
        let totalSeconds = totalDeciseconds / 10
        let decisecond = totalDeciseconds % 10
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d.%d", hours, minutes, secs, decisecond)
        }
        if minutes > 0 {
            return String(format: "%d:%02d.%d", minutes, secs, decisecond)
        }
        return String(format: "%d.%d", secs, decisecond)
    }
}
