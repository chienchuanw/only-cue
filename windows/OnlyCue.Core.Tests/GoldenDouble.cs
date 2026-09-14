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
/// </remarks>
internal static class GoldenDouble
{
    public static double Parse(string text)
    {
        // Swift writes "inf"/"-inf"/"nan"; .NET's invariant culture spells them
        // differently, so handle them before falling back to the numeric parse.
        switch (text)
        {
            case "inf": return double.PositiveInfinity;
            case "-inf": return double.NegativeInfinity;
            case "nan": return double.NaN;
            default:
                return double.TryParse(text, NumberStyles.Float, CultureInfo.InvariantCulture, out var value)
                    ? value
                    : throw new InvalidDataException($"'{text}' is not a parseable double");
        }
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
