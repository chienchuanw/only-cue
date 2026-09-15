using System.Globalization;

namespace OnlyCue.Core.Tests;

/// <summary>
/// Reads the M1 contract's round-trip-exact decimal strings back into IEEE-754
/// doubles, and compares them the way the contract specifies: by bit pattern.
/// </summary>
/// <remarks>
/// The vectors carry doubles as strings rather than JSON numbers because Swift's
/// and .NET's shortest-representation formatters spell the same value
/// differently (<c>1.0</c> vs <c>1</c>, <c>1e-05</c> vs <c>1E-05</c>), which would
/// read as drift that isn't there. The string is transport only — see
/// <c>OnlyCueTests/Support/GoldenDouble.swift</c> for the writing half.
///
/// Bit-pattern comparison (not <c>==</c>) is deliberate: it keeps <c>-0.0</c>
/// distinct from <c>0.0</c> and makes <c>NaN</c> equal itself, so a vector can
/// pin those instead of silently passing them.
///
/// NaN arrives as <c>nan:0x&lt;16 hex digits&gt;</c> rather than as a mnemonic,
/// because no text this runtime understands can name the NaN Swift writes
/// (#833). Measured: Swift's <c>Double.nan</c>, and every NaN obtained by
/// widening a binary32 NaN, is <c>0x7FF8000000000000</c>; <c>double.NaN</c> here
/// is <c>0xFFF8000000000000</c>, and <c>TryParse</c> maps <em>both</em>
/// <c>"nan"</c> and <c>"-nan"</c> onto that sign-bit-set pattern. So the
/// mnemonics are now refused rather than reinterpreted — accepting one would mean
/// choosing a sign on the writer's behalf.
/// </remarks>
internal static class GoldenDouble
{
    private const string NanMarker = "nan:0x";

    /// <summary>The characters Swift's <c>description</c> emits for a finite
    /// double. Restricting the fallback to them refuses, in one place, every
    /// spelling exactly one platform accepts: <c>"NaN"</c>/<c>"Infinity"</c>
    /// (.NET only) and hex floats like <c>0x1p3</c> (Swift only, where it is
    /// silently 8.0).</summary>
    private const string DecimalCharacters = "0123456789+-.eE";

    public static double Parse(string text)
    {
        if (text.StartsWith(NanMarker, StringComparison.Ordinal))
        {
            var hex = text.AsSpan(NanMarker.Length);
            return hex.Length == 16 && long.TryParse(hex, NumberStyles.HexNumber, CultureInfo.InvariantCulture, out var bits)
                ? BitConverter.Int64BitsToDouble(bits)
                : throw new InvalidDataException($"'{text}' is not a 64-bit NaN pattern");
        }

        // The infinities keep their mnemonics — one bit pattern each, so nothing
        // is lost — and .NET's invariant culture does not spell them this way.
        switch (text)
        {
            case "inf": return double.PositiveInfinity;
            case "-inf": return double.NegativeInfinity;
        }

        if (text.Length == 0 || text.AsSpan().IndexOfAnyExcept(DecimalCharacters) >= 0)
        {
            throw new InvalidDataException($"'{text}' is not a spelling the contract writes");
        }

        return double.TryParse(text, NumberStyles.Float, CultureInfo.InvariantCulture, out var value)
            ? value
            : throw new InvalidDataException($"'{text}' is not a parseable double");
    }

    /// <summary>The optional form. A <c>null</c> in the vector is a real result —
    /// "no grid line here", "this cue was left unassigned" — not a missing case.</summary>
    public static double? ParseOrNull(string? text) => text is null ? null : Parse(text);

    public static bool BitwiseEquals(double expected, double actual) =>
        BitConverter.DoubleToInt64Bits(expected) == BitConverter.DoubleToInt64Bits(actual);

    public static bool BitwiseEquals(double? expected, double? actual) =>
        (expected, actual) switch
        {
            (null, null) => true,
            ({ } lhs, { } rhs) => BitwiseEquals(lhs, rhs),
            _ => false
        };

    /// <summary>A description that distinguishes values the shortest form hides —
    /// used only in assertion messages.</summary>
    public static string Describe(double? value) =>
        value is { } number
            ? $"{number.ToString("R", CultureInfo.InvariantCulture)} (0x{BitConverter.DoubleToInt64Bits(number):X16})"
            : "null";
}
