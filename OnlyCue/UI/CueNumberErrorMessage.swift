import Foundation

/// Maps a `CueNumberValidator.Result` to the inline-error string shown under
/// the number field in the inspector and cue-list row. Pure so it can be
/// unit-tested without spinning up a SwiftUI host.
enum CueNumberErrorMessage {

    static let invalidFormat: String = {
        let lo = FadeTime.formatNumber(CueNumberValidator.minimum)
        let hi = FadeTime.formatNumber(CueNumberValidator.maximum)
        return "Use \(lo)–\(hi), up to 3 decimals."
    }()
    static let duplicate = "Already in use."

    /// Returns the user-facing message for a non-`.ok` validator result, or `nil`
    /// if the result is `.ok`.
    static func text(for result: CueNumberValidator.Result) -> String? {
        switch result {
        case .ok:
            return nil
        case .invalidFormat:
            return invalidFormat
        case .duplicate:
            return duplicate
        case .outOfRange(let lower, let upper):
            return outOfRangeText(lower: lower, upper: upper)
        }
    }

    private static func outOfRangeText(lower: Double?, upper: Double?) -> String {
        switch (lower, upper) {
        case let (.some(lo), .some(hi)):
            return "Must be between \(FadeTime.formatNumber(lo)) and \(FadeTime.formatNumber(hi))."
        case let (.some(lo), nil):
            return "Must be greater than \(FadeTime.formatNumber(lo))."
        case let (nil, .some(hi)):
            return "Must be less than \(FadeTime.formatNumber(hi))."
        case (nil, nil):
            // Validator never produces `.outOfRange` with both bounds nil, but
            // fall back to the format message rather than asserting in a UI helper.
            return invalidFormat
        }
    }
}
