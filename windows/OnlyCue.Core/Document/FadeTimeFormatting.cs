using System.Globalization;

namespace OnlyCue.Core.Document;

/// <summary>
/// Canonical number formatting for fade times. Mirrors Swift
/// <c>FadeTime.formatNumber</c> (<c>OnlyCue/Document/FadeTime.swift</c>).
/// </summary>
/// <remarks>
/// This is the one place in the MA2 contract where a <see cref="double"/>'s
/// <i>spelling</i>, not its value, goes on the wire: the result is interpolated
/// straight into an <c>Assign … /fade=</c> telnet command and a
/// <c>basic_fade=</c> XML attribute. <c>GoldenDouble</c> cannot help here —
/// <c>golden/ma2-telnet-v1.json</c> pins the literal strings.
///
/// Swift's <c>String(Double)</c> and .NET's <c>"R"</c> both emit the shortest
/// representation that round-trips, and they agree digit for digit. They differ
/// in two places, both handled below:
///
/// <list type="number">
/// <item>Whole numbers. Swift would spell <c>3.0</c> as <c>"3.0"</c>, so the
/// Swift implementation deliberately routes them through <c>Int(exactly:)</c>
/// to get <c>"3"</c>. The same branch is reproduced here, including its range
/// limit — see <see cref="MinWhole"/>.</item>
/// <item>Exponent case. Both switch to exponential notation under 1e-4 and
/// above the <see cref="long"/> range, but Swift writes <c>e</c> and .NET
/// writes <c>E</c>. Reachable at both ends — <c>FadeTime.parse("0.00001")</c>
/// is accepted, and a decoded fade can exceed the long range — so the marker
/// is lowercased.</item>
/// <item>Non-finite. Swift's <c>String(Double)</c> writes <c>inf</c> /
/// <c>-inf</c> / <c>nan</c> where .NET's <c>"R"</c> writes <c>Infinity</c> /
/// <c>-Infinity</c> / <c>NaN</c>, so those three are spelled explicitly.</item>
/// </list>
/// </remarks>
public static class FadeTimeFormatting
{
    /// <summary>-2^63, the most negative double Swift's <c>Int(exactly:)</c> accepts.</summary>
    private const double MinWhole = -9223372036854775808.0;

    /// <summary>2^63 — exclusive, because <c>long.MaxValue</c> itself is not a double.</summary>
    private const double MaxWholeExclusive = 9223372036854775808.0;

    public static string FormatNumber(double seconds)
    {
        // Swift: `if let whole = Int(exactly: seconds)`. `Int(exactly:)` rejects
        // non-integral, out-of-Int64 and non-finite values alike; `(long)` in
        // C# rejects none of them — it saturates, so an unguarded cast would
        // spell 1e21 and +infinity as `9223372036854775807` where Swift falls
        // through to the double's own spelling (#829). NaN and both infinities
        // fail these comparisons, so the guard covers them too.
        if (seconds >= MinWhole && seconds < MaxWholeExclusive && seconds == Math.Round(seconds))
        {
            // Math.Round's default is banker's, but on an already-integral value
            // every rounding mode agrees, so the comparison is mode-independent.
            return ((long)seconds).ToString(CultureInfo.InvariantCulture);
        }

        if (double.IsNaN(seconds))
        {
            return "nan";
        }

        if (double.IsInfinity(seconds))
        {
            return seconds > 0 ? "inf" : "-inf";
        }

        // 'E' can only ever be the exponent marker in an invariant-culture
        // numeric string, so a blanket lowercase is safe.
        return seconds.ToString("R", CultureInfo.InvariantCulture).Replace('E', 'e');
    }
}
