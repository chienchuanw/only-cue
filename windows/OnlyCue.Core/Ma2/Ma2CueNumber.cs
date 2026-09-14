using System.Globalization;

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
    /// The cast is to <c>long</c>, not <c>int</c>: Swift's <c>Int</c> is 64-bit,
    /// and a <c>(int)</c> cast saturates at 2147483647 on .NET Core 3.0+, so a
    /// cue number above ~2.1 million would silently clamp on Windows while macOS
    /// kept counting. Beyond <c>Int64</c> the two still part ways — Swift traps,
    /// C# saturates — which is the same corrupt-file-only reach as #829.
    ///
    /// Negative values are reproduced as-is rather than corrected: C#'s integer
    /// division and remainder truncate toward zero exactly as Swift's do, so
    /// <c>-1.5</c> yields <c>(-1, -500)</c> on both sides. That is a latent macOS
    /// bug — it renders as the nonsense token <c>-1.-5</c>, which the console
    /// rejects (#830) — but the contract's job is to keep the two cores identical,
    /// so the drift guard will force this side to follow when macOS is fixed.
    /// </remarks>
    public static Components Split(double value)
    {
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
        // width of three *including the sign*, so -5 renders as "-05". .NET's
        // "D3" pads the digits instead and would render "-005"; the two agree
        // only when |subNumber| >= 100, which is why a vector pinning just -1.5
        // (sub -500) could not tell them apart. Spelled out rather than
        // formatted so the width arithmetic is visible.
        var digits = Math.Abs(parts.SubNumber).ToString(CultureInfo.InvariantCulture);
        var sign = parts.SubNumber < 0 ? "-" : string.Empty;
        var frac = (sign + digits.PadLeft(3 - sign.Length, '0')).TrimEnd('0');
        return $"{parts.Number.ToString(CultureInfo.InvariantCulture)}.{frac}";
    }
}
