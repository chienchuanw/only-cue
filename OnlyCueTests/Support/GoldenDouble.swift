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
///
/// NaN travels as `nan:0x<16 hex digits>` rather than as a mnemonic, because a
/// mnemonic cannot name it (#833). Measured on both runtimes: Swift's
/// `Double.nan` — and every NaN that comes out of widening a binary32 NaN — is
/// `0x7FF8000000000000`, while .NET's `double.NaN` is `0xFFF8000000000000`, and
/// .NET's `TryParse` maps *both* `"nan"` and `"-nan"` onto the sign-bit-set
/// pattern. So no text .NET understands can name the value Swift writes, and the
/// bitwise comparison this contract runs on would report drift that isn't there.
/// The `nan:` marker is not decoration: `Double("0x7FF8000000000000")` is
/// **9.221120237041091e+18** on Swift — a plausible finite number, silently —
/// where .NET refuses it, so a bare-hex spelling would have been the one carrier
/// worse than the mnemonic. `inf` / `-inf` have a single bit pattern each and are
/// left as they are.
struct GoldenDouble: Codable, Equatable, ExpressibleByFloatLiteral, ExpressibleByIntegerLiteral {

    /// What a NaN's bit pattern is prefixed with in the vector text.
    private static let nanMarker = "nan:0x"

    /// The characters Swift's `description` can emit for a finite `Double`.
    /// Anything else — a hex float, a mnemonic, stray whitespace — is refused
    /// rather than handed to `Double(_:)`, whose acceptance differs from .NET's
    /// in both directions.
    private static let decimalCharacters = Set("0123456789+-.eE")

    let value: Double

    init(_ value: Double) { self.value = value }

    init(floatLiteral value: Double) { self.init(value) }

    init(integerLiteral value: Int) { self.init(Double(value)) }

    init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let parsed = Self.parse(text) else {
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "\(text) is not a parseable Double"
            )
        }
        self.init(parsed)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        // Swift's `description` is the shortest string that round-trips — except
        // for NaN, where it is a mnemonic (`nan`, or `nan(0x1)` for a payload,
        // which `Double(_:)` cannot even read back).
        guard !value.isNaN else {
            try container.encode(Self.nanMarker + String(format: "%016llX", value.bitPattern))
            return
        }
        try container.encode("\(value)")
    }

    private static func parse(_ text: String) -> Double? {
        if let hex = text.hasPrefix(nanMarker) ? text.dropFirst(nanMarker.count) : nil {
            guard hex.count == 16, let bits = UInt64(hex, radix: 16) else { return nil }
            return Double(bitPattern: bits)
        }
        if text == "inf" { return .infinity }
        if text == "-inf" { return -.infinity }
        guard !text.isEmpty, text.allSatisfy(decimalCharacters.contains) else { return nil }
        return Double(text)
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
