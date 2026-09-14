using System.Globalization;
using OnlyCue.Core.Planning;

namespace OnlyCue.Core.Ma2;

/// <summary>
/// Splits an OnlyCue cue number into grandMA2's <c>number</c> +
/// <c>sub_number</c>. Mirrors Swift <c>MA2CueNumber</c>
/// (<c>OnlyCue/MA2/MA2SequenceXMLGenerator.swift</c>).
/// </summary>
public static class Ma2CueNumber
{
    public readonly record struct Components(long Number, long SubNumber);

    /// <summary>
    /// Rounds in integer thousandths so binary float noise (1.3 → 1300.0002)
    /// cannot leak into the sub number.
    /// </summary>
    /// <remarks>
    /// Swift's <c>.rounded()</c> is round-half-<b>away-from-zero</b>;
    /// <c>Math.Round(double)</c> defaults to banker's rounding and a bare
    /// <c>(long)</c> cast truncates. Both would disagree with macOS on an exact
    /// midpoint — <c>0.0125 * 1000</c> is precisely 12.5 — which
    /// <c>golden/ma2-telnet-v1.json</c> pins.
    ///
    /// Outside <see cref="CueNumberDomain"/> the split collapses to an unnumbered
    /// cue (#830), matching Swift. Two whole classes of divergence go with it:
    /// a negative value used to yield <c>(-1, -500)</c> on both sides and render
    /// as the nonsense token <c>-1.-5</c> that the console rejects; and beyond
    /// <c>Int64</c> the two cores parted ways outright, Swift trapping where C#
    /// saturates. In domain the scaled value tops out at 9_999_999, so even the
    /// <c>int</c>-vs-<c>long</c> width question is now moot — the cast stays
    /// <c>long</c> to keep matching Swift's <c>Int</c> by construction.
    /// </remarks>
    public static Components Split(double value)
    {
        if (!CueNumberDomain.IsInDomain(value))
        {
            return new Components(0, 0);
        }

        var thousandths = (long)Math.Round(value * 1000, MidpointRounding.AwayFromZero);
        return new Components(thousandths / 1000, thousandths % 1000);
    }

    /// <summary>
    /// Cue number as an MA2 command token: an integer when whole, else up to
    /// three decimals with trailing zeros trimmed (<c>1.15</c>, <c>2.001</c>,
    /// <c>3</c>).
    /// </summary>
    public static string CommandString(double value)
    {
        var parts = Split(value);
        if (parts.SubNumber == 0)
        {
            return parts.Number.ToString(CultureInfo.InvariantCulture);
        }

        // Swift: `String(format: "%03d", subNumber)`. `%03d` pads to a total
        // width of three *including the sign*, where .NET's "D3" pads the digits
        // and prepends it — so the two used to disagree on every negative sub
        // number with |value| < 100 ("-05" vs "-005"). `Split`'s domain guard
        // (#830) now keeps the sub number in 0...999, where the two formats are
        // identical, so the sign arithmetic that reconciled them is gone.
        var frac = parts.SubNumber.ToString("D3", CultureInfo.InvariantCulture).TrimEnd('0');
        return $"{parts.Number.ToString(CultureInfo.InvariantCulture)}.{frac}";
    }
}
