import Foundation

struct FadeTime: Codable, Equatable, Hashable {
    var fadeIn: TimeInterval
    var fadeOut: TimeInterval
}

extension FadeTime {

    /// Parses a fade-time string. Accepts `"1"`, `"1.5"` (symmetric) and `"1/2"` (split: in=1, out=2).
    /// Trims surrounding whitespace; rejects empty, non-numeric, negative, multi-slash, or half-empty inputs.
    static func parse(_ s: String) -> FadeTime? {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
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

    private static func parseNonNegative(_ s: Substring) -> TimeInterval? {
        guard !s.isEmpty, let value = Double(s), value >= 0 else { return nil }
        return value
    }
}
