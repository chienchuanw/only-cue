import Foundation

enum TimeFormat {
    /// Formats `seconds` as SMPTE timecode `HH:MM:SS:FF` (`HH:MM:SS;FF` for
    /// drop-frame) at the given `rate`. Negative values clamp to zero; sub-frame
    /// values round half-away-from-zero (inherited from `Timecode`).
    static func smpte(_ seconds: TimeInterval, rate: SMPTEFramerate) -> String {
        Timecode(totalSeconds: max(0, seconds), rate: rate).displayString
    }

    /// Compact SMPTE countdown for trend displays:
    /// - Sub-minute: `"SS:FF"`
    /// - Sub-hour:   `"M:SS:FF"`
    /// - Hour-plus:  `"H:MM:SS:FF"`
    /// Drop-frame uses `;` between SS and FF, matching `Timecode.displayString`.
    /// Negative values clamp to zero; sub-frame values round half-away-from-zero.
    static func smpteCountdown(_ seconds: TimeInterval, rate: SMPTEFramerate) -> String {
        let tc = Timecode(totalSeconds: max(0, seconds), rate: rate)
        let sep = rate.isDropFrame ? ";" : ":"
        if tc.hours > 0 {
            return String(format: "%d:%02d:%02d%@%02d", tc.hours, tc.minutes, tc.seconds, sep, tc.frames)
        }
        if tc.minutes > 0 {
            return String(format: "%d:%02d%@%02d", tc.minutes, tc.seconds, sep, tc.frames)
        }
        return String(format: "%02d%@%02d", tc.seconds, sep, tc.frames)
    }

    /// Compact clip *length* display — a duration, not a timecode position, so
    /// it carries no frame field (ADR-028 amendment): `"M:SS"` under an hour,
    /// `"H:MM:SS"` from an hour up. Matches the Figma media sidebar (`318:1238`,
    /// e.g. `3:42`). Negative values clamp to zero; the fractional second is
    /// truncated (a clip in its Nth second reads N).
    static func compactDuration(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}
