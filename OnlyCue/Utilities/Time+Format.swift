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
}
