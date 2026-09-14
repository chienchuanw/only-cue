import Foundation

/// A `Double` carried through a golden vector as a **round-trip-exact decimal
/// string** rather than a JSON number.
///
/// The M1 contract (`docs/superpowers/specs/2026-09-14-windows-m1-contract-design.md`)
/// requires this because Swift's and .NET's shortest-representation formatters do
/// not spell the same value the same way — Swift writes `1.0` and `1e-05` where
/// .NET's `"R"` writes `1` and `1E-05`. Comparing the *text* would therefore
/// report drift that isn't there. The string is only transport: both cores parse
/// it back to an IEEE-754 `double` and compare bit patterns.
///
/// Bit-pattern equality (not `==`) is deliberate. It makes `-0.0` distinct from
/// `0.0` and `NaN` equal to itself, so a vector can pin those cases instead of
/// silently passing them.
struct GoldenDouble: Codable, Equatable, ExpressibleByFloatLiteral, ExpressibleByIntegerLiteral {

    let value: Double

    init(_ value: Double) { self.value = value }

    init(floatLiteral value: Double) { self.init(value) }

    init(integerLiteral value: Int) { self.init(Double(value)) }

    init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let parsed = Double(text) else {
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "\(text) is not a parseable Double"
            )
        }
        self.init(parsed)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        // Swift's default `description` is the shortest string that round-trips.
        try container.encode("\(value)")
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.value.bitPattern == rhs.value.bitPattern
    }
}

extension GoldenDouble {
    /// Lifts an optional `Double` without spelling the `map` at every call site.
    init?(_ value: Double?) {
        guard let value else { return nil }
        self.init(value)
    }
}
