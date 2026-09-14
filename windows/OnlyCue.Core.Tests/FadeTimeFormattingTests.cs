using OnlyCue.Core.Document;
using Xunit;

namespace OnlyCue.Core.Tests;

/// <summary>
/// Totality and boundary parity for <see cref="FadeTimeFormatting.FormatNumber"/>
/// against Swift's <c>FadeTime.formatNumber</c> (#829).
/// </summary>
/// <remarks>
/// <para>
/// The golden file pins the fade spellings a <i>plan</i> produces, so it only
/// ever exercises values a plan can hold. It never reached the range where the
/// two languages stop agreeing, and the divergence there is asymmetric in the
/// worst way: Swift's <c>Int(_: Double)</c> <b>traps</b> (SIGTRAP, measured at
/// 1e19, 1e21 and ±infinity) while .NET's <c>(long)</c> cast <b>saturates</b>,
/// so the same input crashes macOS and silently puts
/// <c>9223372036854775807</c> on the wire from Windows.
/// </para>
/// <para>
/// Every expectation below is the <i>measured</i> Swift output on Swift 6.3.3,
/// not a derivation. <c>FadeTimeTests</c> asserts the same values on the macOS
/// side; vector 8 (#837) folds them into the golden file, at which point these
/// hand-written literals can go.
/// </para>
/// </remarks>
public class FadeTimeFormattingTests
{
    [Theory]
    [InlineData(0d, "0")]
    [InlineData(1.5d, "1.5")]
    [InlineData(3600d, "3600")]
    [InlineData(1e-5, "1e-05")]
    [InlineData(0.30000000000000004, "0.30000000000000004")]
    public void FormatNumber_MatchesSwift_ForOrdinaryValues(double seconds, string expected)
    {
        Assert.Equal(expected, FadeTimeFormatting.FormatNumber(seconds));
    }

    // 1e17 is the golden file's "Astronomical" fade. It stays in the
    // whole-number branch and must not move.
    [Theory]
    [InlineData(1e17, "100000000000000000")]
    [InlineData(9223372036854774784d, "9223372036854774784")] // largest double below 2^63
    [InlineData(-9223372036854775808d, "-9223372036854775808")] // exactly -2^63
    public void FormatNumber_KeepsWholeForm_UpToTheInt64Boundary(double seconds, string expected)
    {
        Assert.Equal(expected, FadeTimeFormatting.FormatNumber(seconds));
    }

    // Above the boundary Swift's `Int(exactly:)` returns nil and the value falls
    // through to `String(Double)`. .NET must fall through to "R" at the same
    // point rather than saturating the cast.
    [Theory]
    [InlineData(9223372036854775808d, "9.223372036854776e+18")] // exactly 2^63
    [InlineData(1e19, "1e+19")]
    [InlineData(1e21, "1e+21")]
    [InlineData(1.5e20, "1.5e+20")]
    public void FormatNumber_FallsBackToDoubleSpelling_BeyondInt64(double seconds, string expected)
    {
        Assert.Equal(expected, FadeTimeFormatting.FormatNumber(seconds));
    }

    // Swift spells these "inf" / "-inf" / "nan"; .NET's "R" spells them
    // "Infinity" / "-Infinity" / "NaN". NaN is the one that is reachable in the
    // shipped code today — it never trapped on either side, so the two
    // platforms have simply been disagreeing.
    [Theory]
    [InlineData(double.PositiveInfinity, "inf")]
    [InlineData(double.NegativeInfinity, "-inf")]
    [InlineData(double.NaN, "nan")]
    public void FormatNumber_MatchesSwiftsNonFiniteSpelling(double seconds, string expected)
    {
        Assert.Equal(expected, FadeTimeFormatting.FormatNumber(seconds));
    }
}
