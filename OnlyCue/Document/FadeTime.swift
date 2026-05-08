import Foundation

struct FadeTime: Codable, Equatable, Hashable {
    var fadeIn: TimeInterval
    var fadeOut: TimeInterval
}

extension FadeTime {

    /// No-fade default: `fadeIn == fadeOut == 0`. Use this at construction sites and migration backfills.
    static let zero: FadeTime = .symmetric(0)

    /// Symmetric fade where `fadeIn == fadeOut == seconds`.
    static func symmetric(_ seconds: TimeInterval) -> FadeTime {
        FadeTime(fadeIn: seconds, fadeOut: seconds)
    }

    /// Parses a fade-time string. Accepts `"1"`, `"1.5"` (symmetric) and `"1/2"` (split: in=1, out=2).
    /// See `FadeTimeTests` for the full grammar and rejection set.
    static func parse(_ text: String) -> FadeTime? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let parts = trimmed.split(separator: "/", omittingEmptySubsequences: false)
        switch parts.count {
        case 1:
            guard let value = parseNonNegative(parts[0]) else { return nil }
            return FadeTime(fadeIn: value, fadeOut: value)
        case 2:
            guard let inValue = parseNonNegative(parts[0]),
                  let outValue = parseNonNegative(parts[1]) else { return nil }
            return FadeTime(fadeIn: inValue, fadeOut: outValue)
        default:
            return nil
        }
    }

    /// Canonical user-facing form: `"1.5"` for symmetric, `"1/2"` for split. Drops trailing `.0` on whole numbers.
    func format() -> String {
        if fadeIn == fadeOut {
            return Self.formatNumber(fadeIn)
        }
        return "\(Self.formatNumber(fadeIn))/\(Self.formatNumber(fadeOut))"
    }

    private static func parseNonNegative(_ text: Substring) -> TimeInterval? {
        guard !text.isEmpty,
              !text.hasPrefix("+"),
              let value = Double(text),
              value.isFinite,
              value >= 0
        else { return nil }
        return value
    }

    /// Drops trailing `.0` on whole numbers; otherwise returns `String(value)`.
    /// Reused by the cue inspector to display `cueNumber` in the same canonical form.
    static func formatNumber(_ seconds: TimeInterval) -> String {
        if seconds == seconds.rounded() {
            return String(Int(seconds))
        }
        return String(seconds)
    }
}
