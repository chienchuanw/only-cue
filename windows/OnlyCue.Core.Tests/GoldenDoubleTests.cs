using Xunit;

namespace OnlyCue.Core.Tests;

/// <summary>
/// #833 — the reading half of what <c>OnlyCueTests/GoldenDoubleTests.swift</c>
/// pins on the writing side.
/// </summary>
/// <remarks>
/// The trap this closes, measured on both runtimes rather than assumed: Swift's
/// <c>Double.nan</c> is <c>0x7FF8000000000000</c> and so is every NaN produced by
/// widening a binary32 NaN, while .NET's <c>double.NaN</c> is
/// <c>0xFFF8000000000000</c> — and <c>double.TryParse</c> maps <i>both</i>
/// <c>"nan"</c> and <c>"-nan"</c> onto the sign-bit-set pattern, so no text
/// .NET understands can name the one Swift actually writes. Carrying the bits
/// is the only spelling that works in both directions.
/// </remarks>
public class GoldenDoubleTests
{
    /// <summary>The acceptance case from #833.</summary>
    [Fact]
    public void Parse_CarriesTheNaNSwiftActuallyWrites()
    {
        var widened = (double)BitConverter.Int32BitsToSingle(0x7FC00000);

        Assert.True(GoldenDouble.BitwiseEquals(GoldenDouble.Parse("nan:0x7FF8000000000000"), widened));
    }

    /// <summary>
    /// The other half of the acceptance: the two NaNs must stay distinguishable.
    /// Before the fix this comparison could not even be expressed — every NaN
    /// spelling collapsed onto <c>double.NaN</c>.
    /// </summary>
    [Fact]
    public void Parse_KeepsTheSignedNaNDistinctFromTheUnsignedOne()
    {
        var unsigned = GoldenDouble.Parse("nan:0x7FF8000000000000");
        var signed = GoldenDouble.Parse("nan:0xFFF8000000000000");

        Assert.False(GoldenDouble.BitwiseEquals(unsigned, signed));
        Assert.True(GoldenDouble.BitwiseEquals(signed, double.NaN));
    }

    [Fact]
    public void Parse_KeepsANaNPayload()
    {
        var parsed = GoldenDouble.Parse("nan:0x7FF8000000000001");

        Assert.Equal(0x7FF8000000000001, BitConverter.DoubleToInt64Bits(parsed));
    }

    /// <summary>
    /// Refused rather than reinterpreted. Accepting a mnemonic would mean
    /// choosing a sign on the writer's behalf, and the two platforms choose
    /// differently — which is the defect itself.
    /// </summary>
    [Theory]
    [InlineData("nan")]
    [InlineData("-nan")]
    [InlineData("NaN")]
    [InlineData("Infinity")]
    [InlineData("-Infinity")]
    public void Parse_RejectsSpellingsOnlyOnePlatformUnderstands(string text)
    {
        Assert.Throws<InvalidDataException>(() => GoldenDouble.Parse(text));
    }

    /// <summary>
    /// A regression guard, not a fix: .NET already refuses these. Swift does
    /// not — <c>Double("0x1p3")</c> is 8.0 there — so the Swift reader grew the
    /// matching rejection and this keeps the two from drifting back apart.
    /// </summary>
    [Theory]
    [InlineData("0x7FF8000000000000")]
    [InlineData("0x1p3")]
    [InlineData("0x1F")]
    public void Parse_RejectsHexFloatSpellings(string text)
    {
        Assert.Throws<InvalidDataException>(() => GoldenDouble.Parse(text));
    }

    /// <remarks>
    /// <c>"nan:0x7FF8"</c> earns its place: a mutation run showed every other
    /// case here still failing without the 16-digit length check, because they
    /// are all unparseable hex. A <em>short but valid</em> pattern is the one
    /// that goes quietly wrong — it reads back as <c>0x7FF8</c>, a denormal
    /// around 1.6e-319, which is a finite number where a NaN was meant.
    /// </remarks>
    [Theory]
    [InlineData("nan:0x")]
    [InlineData("nan:0x7FF8")]
    [InlineData("nan:0x0")]
    [InlineData("nan:0xZZZ8000000000000")]
    [InlineData("nan:7FF8000000000000")]
    [InlineData("nan:0x7FF80000000000000")]
    public void Parse_RejectsAMalformedBitPattern(string text)
    {
        Assert.Throws<InvalidDataException>(() => GoldenDouble.Parse(text));
    }

    /// <summary>The infinities have one bit pattern each, so their mnemonics are
    /// lossless and stay as they were. This pins that the NaN change left
    /// them — and the ordinary decimals — alone.</summary>
    [Theory]
    [InlineData("inf", 0x7FF0000000000000L)]
    [InlineData("-inf", unchecked((long)0xFFF0000000000000UL))]
    [InlineData("1.0", 0x3FF0000000000000L)]
    [InlineData("-0.0", unchecked((long)0x8000000000000000UL))]
    [InlineData("1e-05", 0x3EE4F8B588E368F1L)]
    public void Parse_LeavesEveryOtherSpellingUnchanged(string text, long bits)
    {
        Assert.Equal(bits, BitConverter.DoubleToInt64Bits(GoldenDouble.Parse(text)));
    }
}
