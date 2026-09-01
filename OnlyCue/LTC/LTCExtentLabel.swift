import Foundation

/// Renders a striped track's measured extent for the edit sheet's status
/// line (#793) — `00:00:02.0 – 00:04:51.1`. Wall-clock position in the
/// media, deliberately not SMPTE: this answers "where in this file", and
/// mixing it with the timecode value in the same line would read as two
/// timecodes.
enum LTCExtentLabel {

    /// `nil` when neither bound is known, so the caller can omit the
    /// segment entirely rather than print a placeholder.
    static func text(validFrom: TimeInterval?, validUntil: TimeInterval?) -> String? {
        switch (validFrom, validUntil) {
        case (nil, nil):
            return nil
        case (let from?, nil):
            return "from \(clock(from))"
        case (nil, let until?):
            return "to \(clock(until))"
        case (let from?, let until?):
            return "\(clock(from)) – \(clock(until))"
        }
    }

    /// HH:MM:SS.t — tenths, because the bounds are measured to within a
    /// frame and a second's resolution would hide a short stripe.
    private static func clock(_ seconds: TimeInterval) -> String {
        let clamped = max(0, seconds)
        let whole = Int(clamped)
        let tenths = Int((clamped - Double(whole)) * 10)
        return String(
            format: "%02d:%02d:%02d.%d",
            whole / 3600, (whole % 3600) / 60, whole % 60, tenths
        )
    }
}
