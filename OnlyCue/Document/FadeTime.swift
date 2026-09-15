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

    /// Upper bound for a single fade leg, in seconds (#829). An hour is well
    /// past any fade a designer types; beyond it the value is corruption, and
    /// it propagates into the MA2 wire payload and the cue-list fade column.
    static let maximum: TimeInterval = 3600

    /// Coerces an untrusted seconds value into `0...maximum`.
    ///
    /// NaN / infinity defeats min/max clamping, so it drops to zero rather than
    /// propagating — the same choice `Cue.init` already makes for `bpm`.
    static func clamped(_ seconds: TimeInterval) -> TimeInterval {
        guard seconds.isFinite else { return 0 }
        return min(max(seconds, 0), maximum)
    }

    /// File trust boundary: a `.cuelist` is hand-editable and can be corrupt, so
    /// both legs are clamped on the way in (#829).
    ///
    /// Deliberately *not* mirrored in the memberwise initialiser — in-process
    /// construction is trusted, and the MA2 golden vectors seat an out-of-range
    /// fade on purpose to pin cross-platform formatter parity.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            fadeIn: Self.clamped(try container.decode(TimeInterval.self, forKey: .fadeIn)),
            fadeOut: Self.clamped(try container.decode(TimeInterval.self, forKey: .fadeOut))
        )
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

    /// Cue-list fade cell text. Seconds is the column's implicit unit, so the
    /// cell shows the bare number in canonical `format()` form (whole values
    /// drop the trailing `.0`, split fades render as `"1/2"`) and blanks a zero
    /// fade so an unset fade reads as absence rather than `"0"` (#804).
    var cellDisplay: String {
        self == .zero ? "" : format()
    }

    private static func parseNonNegative(_ text: Substring) -> TimeInterval? {
        guard !text.isEmpty,
              !text.hasPrefix("+"),
              !isHexFloat(text),
              let value = Double(text),
              value.isFinite,
              value >= 0,
              value <= maximum
        else { return nil }
        return value
    }

    /// `Double(String)` implements the whole C99 `strtod` grammar, so `"0x1p3"`
    /// would otherwise be accepted as an 8 second fade (#841). Nothing in the
    /// fade grammar intends that, and .NET has no hex-float parse at all, so the
    /// Windows core could not agree without one (epic #728).
    ///
    /// The sign is stepped over rather than left to the `value >= 0` guard
    /// below: `"-0x0p0"` reaches `-0.0`, and `-0.0 >= 0` is true.
    private static func isHexFloat(_ text: Substring) -> Bool {
        let body = text.hasPrefix("-") ? text.dropFirst() : text
        return body.hasPrefix("0x") || body.hasPrefix("0X")
    }

    /// Drops trailing `.0` on whole numbers; otherwise returns `String(value)`.
    /// Reused by the cue inspector to display `cueNumber` in the same canonical form.
    ///
    /// `Int(exactly:)` rather than `Int(_:)`: the plain conversion traps on any
    /// whole value outside `Int64` (from 1e19 up) and on infinity, and this
    /// formatter also renders `cueNumber`, which has no clamp of its own (#829).
    static func formatNumber(_ seconds: TimeInterval) -> String {
        if let whole = Int(exactly: seconds) {
            return String(whole)
        }
        return String(seconds)
    }
}
