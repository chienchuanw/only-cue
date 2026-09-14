import Foundation

/// Inputs for vector 8's two fade groups. Only inputs — the expectations are
/// whatever the Swift implementation produces, which is what makes macOS the
/// source of truth rather than a second opinion.
enum CuePresentationFadeFixtures {

    /// Strings fed to `FadeTime.parse`.
    ///
    /// The four confirmed Swift/.NET divergences are the reason this group is
    /// the longest (measured on Swift 6.3.3 / .NET 10.0.11, not assumed):
    ///
    /// - **newline / carriage return.** Swift's `.whitespaces` is Unicode `Zs`
    ///   plus tab and excludes line separators, so `"1.5\n"` does *not* trim and
    ///   `Double("1.5\n")` then fails. .NET's `Trim()` strips them, so a naive
    ///   port accepts. Tab and NBSP are in the set on both sides and agree —
    ///   pinned too, so the port cannot "fix" the divergence by trimming nothing.
    /// - **hex float.** Swift's `Double(String)` accepts C99 `0x1p3` (= 8);
    ///   .NET's `double.Parse` rejects it.
    /// - **leading plus.** Rejected only by the explicit `hasPrefix("+")` guard;
    ///   .NET's `NumberStyles.Float` allows a leading sign, so dropping the guard
    ///   is invisible without this case.
    /// - **infinity / nan spellings.** .NET `TryParse` accepts both words, so the
    ///   `IsFinite` check is load-bearing on that side where on Swift it is
    ///   belt-and-braces.
    static let parseInputs: [(name: String, input: String)] = [
        ("a whole number is symmetric", "1"),
        ("a decimal is symmetric", "1.5"),
        ("zero is symmetric", "0"),
        ("a slash splits in from out", "1/2"),
        ("a split fade may be asymmetric decimals", "0.5/0.25"),
        ("a split fade may have a zero leg", "0/1"),
        ("the fade maximum is accepted", "3600"),
        ("above the fade maximum is rejected", "3601"),
        ("a trailing point is a whole number", "1."),
        ("a leading point is a fraction", ".5"),
        ("exponent notation is accepted", "1e3"),
        ("an overflowing exponent is not finite and is rejected", "1e400"),
        // Whitespace: the set differs across the two platforms.
        ("surrounding spaces are trimmed", " 1.5 "),
        ("a trailing tab is trimmed", "1.5\t"),
        ("a leading no-break space is trimmed", "\u{00A0}1.5"),
        ("a trailing newline is NOT trimmed and is rejected", "1.5\n"),
        ("a trailing carriage return is NOT trimmed and is rejected", "1.5\r"),
        ("interior whitespace is never trimmed", "1 5"),
        // Number grammar the two platforms read differently.
        ("a C99 hex float is accepted", "0x1p3"),
        ("a leading plus is rejected", "+1"),
        ("a leading plus on the out leg is rejected", "1/+2"),
        ("the word infinity is rejected", "infinity"),
        ("the word nan is rejected", "nan"),
        ("capitalised Infinity is rejected", "Infinity"),
        ("a digit separator is rejected", "1_000"),
        // Rejections that both platforms agree on, pinned so a port cannot
        // loosen them while chasing the divergences above.
        ("a negative fade is rejected", "-1"),
        ("a negative out leg is rejected", "1/-2"),
        ("the empty string is rejected", ""),
        ("blank space is rejected", "   "),
        ("a missing out leg is rejected", "1/"),
        ("a missing in leg is rejected", "/2"),
        ("two slashes are rejected", "1/2/3"),
        ("letters are rejected", "abc")
    ]

    /// `(fadeIn, fadeOut)` pairs fed to `FadeTime.format` and `.cellDisplay`.
    static let formatInputs: [CuePresentationFormatInput] = [
        .init(name: "a zero fade formats as 0 but its cell is blank", fadeIn: 0, fadeOut: 0),
        .init(name: "a symmetric whole number drops the decimal", fadeIn: 1, fadeOut: 1),
        .init(name: "a symmetric decimal keeps it", fadeIn: 1.5, fadeOut: 1.5),
        .init(name: "a split fade is spelled with a slash", fadeIn: 1, fadeOut: 2),
        .init(name: "a split fade with a zero in leg still shows", fadeIn: 0, fadeOut: 1),
        .init(name: "a split fade with a zero out leg still shows", fadeIn: 1, fadeOut: 0),
        .init(name: "split decimals keep their own spelling", fadeIn: 0.5, fadeOut: 0.25),
        .init(name: "the fade maximum formats as a whole number", fadeIn: 3600, fadeOut: 3600),
        .init(name: "a value needing many digits round-trips", fadeIn: 0.1, fadeOut: 0.30000000000000004)
    ]
}
