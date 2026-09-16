using OnlyCue.Core.Ltc;
using Xunit;

namespace OnlyCue.Core.Tests;

/// <summary>
/// The Windows half of the LTC wire-format contract (epic #728, M2 slice 1).
/// macOS emits <c>golden/ltc-wire-v1.json</c> from the Swift <c>LTCFrame</c> /
/// <c>LTCEncoder</c>; this suite asserts the C# re-implementation reproduces
/// every case exactly, so drift between the two hand-maintained cores fails CI
/// instead of shipping.
/// </summary>
public class LtcWireGoldenVectorTests
{
    private static readonly LtcWireVector Vector = LtcWireVector.Load();

    public static TheoryData<string> CaseLabels
    {
        get
        {
            var data = new TheoryData<string>();
            foreach (var label in Vector.Cases.Select(c => c.Label))
            {
                data.Add(label);
            }

            return data;
        }
    }

    [Fact]
    public void GoldenFile_IsTheExpectedContract()
    {
        Assert.Equal("ltc-wire", Vector.Contract);
        Assert.Equal(1, Vector.Version);
        Assert.NotEmpty(Vector.Cases);
    }

    [Theory]
    [MemberData(nameof(CaseLabels))]
    public void CSharpCore_ReproducesGoldenCase(string label)
    {
        var goldenCase = Vector.Cases.Single(c => c.Label == label);
        var timecode = TimecodeFrom(goldenCase);

        switch (goldenCase.Op)
        {
            case "frame":
                AssertFrame(goldenCase, timecode);
                break;
            case "encode":
                AssertEncode(goldenCase, timecode);
                break;
            default:
                throw new InvalidDataException($"unknown golden op '{goldenCase.Op}'");
        }
    }

    private static void AssertFrame(LtcWireCase goldenCase, Timecode timecode)
    {
        var frame = LtcFrame.FromTimecode(timecode);
        var label = goldenCase.Label;

        Assert.Equal(goldenCase.Expect.Bits, frame.BitString());
        Assert.Equal(goldenCase.Expect.ParityBitIndex, LtcFrame.ParityBitIndex(timecode.Rate));
        Assert.Equal(goldenCase.Expect.ParityBit, frame.Bits[LtcFrame.ParityBitIndex(timecode.Rate)]);
        Assert.Equal(goldenCase.Expect.Bit27, frame.Bits[27]);
        Assert.Equal(goldenCase.Expect.Bit59, frame.Bits[59]);
        Assert.Equal(goldenCase.Expect.HasEvenParity, frame.HasEvenParity);
        Assert.Equal(goldenCase.Expect.SyncWordIsValid, frame.SyncWordIsValid);
        Assert.True(frame.HasEvenParity, $"{label}: every LTC word leaves with even parity");
    }

    private static void AssertEncode(LtcWireCase goldenCase, Timecode timecode)
    {
        var label = goldenCase.Label;
        var sampleRate = GoldenDouble.Parse(
            goldenCase.Input.SampleRate ?? throw new InvalidDataException($"{label} has no sampleRate"));
        var amplitude = (float)GoldenDouble.Parse(
            goldenCase.Input.Amplitude ?? throw new InvalidDataException($"{label} has no amplitude"));
        var startLevel = goldenCase.Input.StartLevel
            ?? throw new InvalidDataException($"{label} has no startLevel");

        var (samples, endLevel) = LtcEncoder.Samples(timecode, sampleRate, amplitude, startLevel);

        Assert.Equal(goldenCase.Expect.TotalSamples, samples.Length);
        Assert.Equal(goldenCase.Expect.EndLevel, endLevel);
        Assert.Equal(goldenCase.Expect.Runs, RunLengths(samples));

        // The runs carry only the sign, so the amplitude is asserted separately —
        // at `float`, never widened to `double`, because that is the precision
        // both cores actually hold it at.
        Assert.All(samples, sample => Assert.Equal(amplitude, Math.Abs(sample)));
    }

    private static Timecode TimecodeFrom(LtcWireCase goldenCase)
    {
        var rate = SmpteFramerateExtensions.FromRawValue(goldenCase.Rate);
        return Timecode.Create(
                   goldenCase.Input.Hours,
                   goldenCase.Input.Minutes,
                   goldenCase.Input.Seconds,
                   goldenCase.Input.Frames,
                   rate)
               ?? throw new InvalidDataException($"{goldenCase.Label} does not name a valid timecode");
    }

    /// <summary>Run-length encodes a <c>±amplitude</c> signal the way the
    /// contract spells it: <c>[[sign, sampleCount], …]</c>.</summary>
    private static List<IReadOnlyList<int>> RunLengths(IReadOnlyList<float> samples)
    {
        var runs = new List<IReadOnlyList<int>>();
        foreach (var sample in samples)
        {
            var sign = sample < 0 ? -1 : 1;
            if (runs.Count > 0 && runs[^1][0] == sign)
            {
                runs[^1] = new[] { sign, runs[^1][1] + 1 };
            }
            else
            {
                runs.Add(new[] { sign, 1 });
            }
        }

        return runs;
    }

    /// <summary>
    /// The trap the 24 fps / 48 kHz case exists to catch, pinned independently of
    /// the vectors. <c>halfBitSamples</c> is exactly 12.5 there, so every odd slot
    /// boundary is a midpoint tie — and .NET's default <c>Math.Round</c> is
    /// banker's rounding, which lands on the *even* neighbour, while Swift's
    /// <c>.rounded()</c> goes away from zero. Without the explicit
    /// <c>MidpointRounding.AwayFromZero</c> in <see cref="LtcEncoder"/> every
    /// other run would be one sample short.
    /// </summary>
    [Fact]
    public void DotNetDefaultRounding_DisagreesWithSwift_AtTheMidpoint()
    {
        const double halfBitSamples = 48000.0 / (160.0 * 24.0);
        Assert.Equal(12.5, halfBitSamples);

        Assert.Equal(12, Math.Round(halfBitSamples));                               // banker's — wrong here
        Assert.Equal(13, Math.Round(halfBitSamples, MidpointRounding.AwayFromZero)); // Swift's rule
        Assert.Equal(38, Math.Round(3 * halfBitSamples, MidpointRounding.AwayFromZero));
    }

    /// <summary>
    /// Independent hand-computed pins, mirroring <c>test_knownWireValues</c> on
    /// the Swift side. Without these a wrong C# implementation could still be
    /// "verified" if the golden file were ever regenerated from a wrong source.
    /// </summary>
    [Fact]
    public void SyncWord_AndParityPlacement_MatchSmpte12M()
    {
        var at25 = Timecode.Create(1, 2, 3, 4, SmpteFramerate.Fps25)!.Value;
        var frame = LtcFrame.FromTimecode(at25);

        Assert.Equal("0011111111111101", frame.BitString()[64..]);
        // 01:02:03:04 at 25 fps needs no correction, so neither candidate is set.
        Assert.False(frame.Bits[27]);
        Assert.False(frame.Bits[59]);

        Assert.Equal(59, LtcFrame.ParityBitIndex(SmpteFramerate.Fps25));
        Assert.Equal(27, LtcFrame.ParityBitIndex(SmpteFramerate.Fps24));
        Assert.Equal(27, LtcFrame.ParityBitIndex(SmpteFramerate.Fps30));
        Assert.Equal(27, LtcFrame.ParityBitIndex(SmpteFramerate.Fps30Drop));
    }

    /// <summary>A non-positive sample rate traps on macOS
    /// (<c>precondition</c>); it must fail here too rather than quietly
    /// returning nothing.</summary>
    [Fact]
    public void NonPositiveSampleRate_Throws()
    {
        var timecode = Timecode.Create(0, 0, 0, 0, SmpteFramerate.Fps25)!.Value;
        Assert.Throws<ArgumentOutOfRangeException>(() => LtcEncoder.Samples(timecode, 0));
        Assert.Throws<ArgumentOutOfRangeException>(() => LtcEncoder.Samples(timecode, -48000));
    }
}
