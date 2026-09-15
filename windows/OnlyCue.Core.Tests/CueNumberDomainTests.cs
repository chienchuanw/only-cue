using OnlyCue.Core.Document;
using OnlyCue.Core.Ma2;
using OnlyCue.Core.Planning;
using Xunit;

namespace OnlyCue.Core.Tests;

/// <summary>
/// #830 — grandMA2's <c>0.001...9999.999</c> numbering window, mirrored from
/// Swift <c>CueNumberValidator.isInDomain</c>.
/// </summary>
/// <remarks>
/// <para>
/// <c>golden/ma2-telnet-v1.json</c> pins the finite cases, so these cover the
/// decode-side coercion, which has no vector because it is a <i>document</i>
/// boundary rather than a formatter. The non-finite inputs stay here as direct
/// assertions, but they are no longer vector-impossible: since #833
/// <c>GoldenDouble</c> carries bit patterns, and
/// <c>golden/cue-presentation-v1.json</c> pins <c>nan</c> and <c>inf</c> as
/// format errors on both sides.
/// </para>
/// <para>
/// The Swift side asserts the same values in <c>CueNumberDomainTests</c> and
/// <c>MA2SequenceXMLGeneratorTests</c>.
/// </para>
/// </remarks>
public class CueNumberDomainTests
{
    [Theory]
    [InlineData(0.001)]
    [InlineData(1.5)]
    [InlineData(9999.999)]
    public void IsInDomain_AcceptsTheNumberingWindow(double value)
    {
        Assert.True(CueNumberDomain.IsInDomain(value));
    }

    [Theory]
    [InlineData(0d)]
    [InlineData(0.0005)]
    [InlineData(-1.5)]
    [InlineData(10000d)]
    [InlineData(3000000d)]
    [InlineData(1e16)]
    [InlineData(double.NaN)]
    [InlineData(double.PositiveInfinity)]
    [InlineData(double.NegativeInfinity)]
    public void IsInDomain_RejectsEverythingElse(double value)
    {
        Assert.False(CueNumberDomain.IsInDomain(value));
    }

    // Swift's `Int(_: Double)` traps on these; .NET's `(long)` cast saturates
    // instead, so before the guard the same corrupt document crashed macOS and
    // silently put long.MaxValue-derived nonsense on the wire from Windows.
    [Theory]
    [InlineData(double.NaN)]
    [InlineData(double.PositiveInfinity)]
    [InlineData(double.NegativeInfinity)]
    public void Split_IsTotalOverNonFinite(double value)
    {
        Assert.Equal(new Ma2CueNumber.Components(0, 0), Ma2CueNumber.Split(value));
        Assert.Equal("0", Ma2CueNumber.CommandString(value));
    }

    // MARK: decode coercion — Cue.Clamped is where the C# codec does what
    // Swift's `Cue.init(from:)` does.

    [Theory]
    [InlineData(-1.5)]
    [InlineData(0d)]
    [InlineData(0.0005)]
    [InlineData(10000d)]
    [InlineData(1e16)]
    [InlineData(double.NaN)]
    public void Clamped_CoercesAnOutOfDomainCueNumberToNull(double value)
    {
        var cue = new Cue { CueNumber = value }.Clamped();
        Assert.Null(cue.CueNumber);
    }

    [Theory]
    [InlineData(0.001)]
    [InlineData(1.5)]
    // A fourth decimal place is rounded harmlessly into thousandths by both
    // generators, so the window gates on range alone and keeps it.
    [InlineData(1.0005)]
    [InlineData(9999.999)]
    public void Clamped_KeepsAnInDomainCueNumber(double value)
    {
        var cue = new Cue { CueNumber = value }.Clamped();
        Assert.Equal(value, cue.CueNumber);
    }

    [Fact]
    public void Clamped_LeavesAnAbsentCueNumberNull()
    {
        Assert.Null(new Cue().Clamped().CueNumber);
    }

    // #829 left this half-ported: Swift's `FadeTime.init(from:)` clamps both
    // legs to 0...3600 on the way in, but the C# codec filled the properties
    // straight from the deserialiser. No golden vector seats an out-of-range
    // fade in a *document*, so the drift went unnoticed.
    [Theory]
    [InlineData(-5d, 0d)]
    [InlineData(0d, 0d)]
    [InlineData(1.5, 1.5)]
    [InlineData(3600d, 3600d)]
    [InlineData(7200d, 3600d)]
    [InlineData(1e21, 3600d)]
    [InlineData(double.NaN, 0d)]
    [InlineData(double.PositiveInfinity, 0d)]
    public void Clamped_BoundsBothFadeLegs(double seconds, double expected)
    {
        var cue = new Cue { FadeTime = FadeTime.Symmetric(seconds) }.Clamped();
        Assert.Equal(expected, cue.FadeTime.FadeIn);
        Assert.Equal(expected, cue.FadeTime.FadeOut);
    }
}
