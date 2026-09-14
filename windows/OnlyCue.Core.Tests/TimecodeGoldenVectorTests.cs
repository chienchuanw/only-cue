using Xunit;

namespace OnlyCue.Core.Tests;

/// <summary>
/// The Windows half of the cross-platform golden-vector contract (epic #728, M0).
/// macOS emits <c>golden/timecode-v1.json</c> from the Swift <c>Timecode</c>; this
/// suite asserts the C# re-implementation reproduces every case exactly, so drift
/// between the two hand-maintained cores fails CI instead of shipping.
/// </summary>
public class TimecodeGoldenVectorTests
{
    private static readonly GoldenVector Vector = GoldenVector.Load();

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
        Assert.Equal("timecode", Vector.Contract);
        Assert.Equal(1, Vector.Version);
        Assert.NotEmpty(Vector.Cases);
    }

    [Theory]
    [MemberData(nameof(CaseLabels))]
    public void CSharpCore_ReproducesGoldenCase(string label)
    {
        var goldenCase = Vector.Cases.Single(c => c.Label == label);
        var rate = SmpteFramerateExtensions.FromRawValue(goldenCase.Rate);

        Timecode? actual = goldenCase.Op switch
        {
            "fromFrameCount" => Timecode.FromFrameCount(
                goldenCase.Input.FrameCount ?? throw new InvalidDataException($"{label} has no frameCount"),
                rate),
            "fromTotalSeconds" => Timecode.FromTotalSeconds(
                goldenCase.Input.TotalSeconds ?? throw new InvalidDataException($"{label} has no totalSeconds"),
                rate),
            "parse" => Timecode.Parse(
                goldenCase.Input.String ?? throw new InvalidDataException($"{label} has no string"),
                rate),
            _ => throw new InvalidDataException($"unknown golden op '{goldenCase.Op}'")
        };

        if (!goldenCase.Expect.Valid)
        {
            Assert.True(actual is null, $"{label} should be rejected but produced {actual}");
            return;
        }

        Assert.True(actual is not null, $"{label} should produce a timecode but was rejected");
        var timecode = actual!.Value;
        Assert.Equal(goldenCase.Expect.Hours, timecode.Hours);
        Assert.Equal(goldenCase.Expect.Minutes, timecode.Minutes);
        Assert.Equal(goldenCase.Expect.Seconds, timecode.Seconds);
        Assert.Equal(goldenCase.Expect.Frames, timecode.Frames);
        Assert.Equal(goldenCase.Expect.Display, timecode.DisplayString);
        Assert.Equal(goldenCase.Expect.FrameCount, timecode.FrameCount);
    }

    /// <summary>
    /// Independent hand-computed pins, mirroring <c>test_knownDropFrameValues</c>
    /// on the Swift side. Without these a wrong C# implementation could still be
    /// "verified" if the golden file were ever regenerated from a wrong source.
    /// </summary>
    [Fact]
    public void DropFrame_SkipsTwoFramesAtEveryMinuteExceptTheTenth()
    {
        const SmpteFramerate df = SmpteFramerate.Fps30Drop;

        Assert.Equal("00:00:59;29", Timecode.FromFrameCount(1799, df).DisplayString);
        Assert.Equal("00:01:00;02", Timecode.FromFrameCount(1800, df).DisplayString);
        Assert.Equal("00:10:00;00", Timecode.FromFrameCount(17982, df).DisplayString);

        Assert.Equal(1800, Timecode.Create(0, 1, 0, 2, df)!.Value.FrameCount);
        Assert.Equal(17982, Timecode.Create(0, 10, 0, 0, df)!.Value.FrameCount);

        // The skipped labels have no frame behind them.
        Assert.Null(Timecode.Create(0, 1, 0, 0, df));
        Assert.Null(Timecode.Create(0, 1, 0, 1, df));

        // Non-drop sanity.
        Assert.Equal("00:00:01:00", Timecode.FromFrameCount(30, SmpteFramerate.Fps30).DisplayString);
        Assert.Equal("00:00:01:00", Timecode.FromFrameCount(24, SmpteFramerate.Fps24).DisplayString);
    }
}
