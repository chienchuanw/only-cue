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
/// Swift implementation deliberately routes them through <c>String(Int(...))</c>
/// to get <c>"3"</c>. The same branch is reproduced here.</item>
/// <item>Exponent case. Under 1e-4 both switch to exponential notation, but
/// Swift writes <c>1e-05</c> and .NET writes <c>1E-05</c>. Reachable —
/// <c>FadeTime.parse("0.00001")</c> is accepted — so the marker is lowercased.
/// Only the negative exponent matters: every double large enough for a positive
/// exponent is integral, and so takes the whole-number branch above.</item>
/// </list>
/// </remarks>
public static class FadeTimeFormatting
{
    public static string FormatNumber(double seconds)
    {
        // Swift: `if seconds == seconds.rounded()`. Math.Round's default is
        // banker's, but on an already-integral value every rounding mode agrees,
        // so the comparison is mode-independent.
        if (seconds == Math.Round(seconds))
        {
            return ((long)seconds).ToString(CultureInfo.InvariantCulture);
        }

        // 'E' can only ever be the exponent marker in an invariant-culture
        // numeric string, so a blanket lowercase is safe.
        return seconds.ToString("R", CultureInfo.InvariantCulture).Replace('E', 'e');
    }
}
