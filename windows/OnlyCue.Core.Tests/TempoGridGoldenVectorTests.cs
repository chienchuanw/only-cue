using OnlyCue.Core.Document;
using OnlyCue.Core.Tempo;
using Xunit;

namespace OnlyCue.Core.Tests;

/// <summary>
/// The Windows half of the tempo-grid contract (epic #728, M1b — vector 7). macOS
/// emits <c>golden/tempo-grid-v1.json</c> from the Swift <c>DerivedTempoGrid</c>;
/// this suite asserts the C# re-implementation reproduces every segment, beat,
/// bar and snap result bit-for-bit, so drift between the two hand-maintained
/// cores fails CI instead of shipping.
/// </summary>
public class TempoGridGoldenVectorTests
{
    private static readonly TempoGridVector Vector = TempoGridVector.Load();

    public static TheoryData<string> CaseNames
    {
        get
        {
            var data = new TheoryData<string>();
            foreach (var name in Vector.Cases.Select(c => c.Name))
            {
                data.Add(name);
            }

            return data;
        }
    }

    [Fact]
    public void GoldenFile_IsTheExpectedContract()
    {
        Assert.Equal("tempo-grid", Vector.Contract);
        Assert.Equal(1, Vector.Version);
        Assert.NotEmpty(Vector.Cases);
    }

    [Theory]
    [MemberData(nameof(CaseNames))]
    public void CSharpCore_ReproducesGoldenCase(string name)
    {
        var golden = Vector.Cases.Single(c => c.Name == name);
        var itemDuration = GoldenDouble.Parse(golden.ItemDuration);
        var grid = DerivedTempoGrid.From(Cues(golden.Cues));

        AssertSegments(name, golden, grid);
        AssertRanges(name, golden, grid, itemDuration);
        AssertPoints(name, golden, grid, itemDuration);
    }

    private static void AssertSegments(string name, TempoGridCase golden, DerivedTempoGrid grid)
    {
        Assert.True(
            golden.Segments.Count == grid.Segments.Count,
            $"'{name}': expected {golden.Segments.Count} segment(s), got {grid.Segments.Count}");

        foreach (var (expected, actual) in golden.Segments.Zip(grid.Segments))
        {
            Equal(name, "segment.startSeconds", GoldenDouble.Parse(expected.StartSeconds), actual.StartSeconds);
            Equal(name, "segment.bpm", GoldenDouble.Parse(expected.Bpm), actual.Bpm);
            Assert.True(
                expected.BeatsPerBar == actual.BeatsPerBar,
                $"'{name}' segment.beatsPerBar: expected {expected.BeatsPerBar}, got {actual.BeatsPerBar}");
            Equal(name, "segment.beatDuration", GoldenDouble.Parse(expected.BeatDuration), actual.BeatDuration);
            Equal(name, "segment.barDuration", GoldenDouble.Parse(expected.BarDuration), actual.BarDuration);
        }
    }

    private static void AssertRanges(string name, TempoGridCase golden, DerivedTempoGrid grid, double itemDuration)
    {
        foreach (var query in golden.Ranges)
        {
            var lower = GoldenDouble.Parse(query.LowerBound);
            var upper = GoldenDouble.Parse(query.UpperBound);
            var label = $"beatTimes({query.LowerBound}…{query.UpperBound})";

            var beats = grid.BeatTimes(lower, upper, itemDuration);
            Assert.True(
                query.Beats.Count == beats.Count,
                $"'{name}' {label}: expected {query.Beats.Count} beat(s), got {beats.Count} "
                + $"[{string.Join(", ", beats.Select(b => GoldenDouble.Describe(b.Time)))}]");

            foreach (var (expected, actual) in query.Beats.Zip(beats))
            {
                Equal(name, $"{label} time", GoldenDouble.Parse(expected.Time), actual.Time);
                Assert.True(
                    expected.IsDownbeat == actual.IsDownbeat,
                    $"'{name}' {label} at {expected.Time}: expected isDownbeat={expected.IsDownbeat}, "
                    + $"got {actual.IsDownbeat}");
            }

            var bars = grid.BarTimes(lower, upper, itemDuration);
            Assert.True(
                query.Bars.Count == bars.Count,
                $"'{name}' barTimes({query.LowerBound}…{query.UpperBound}): expected {query.Bars.Count} "
                + $"bar(s), got {bars.Count}");
            foreach (var (expected, actual) in query.Bars.Zip(bars))
            {
                Equal(name, "barTimes", GoldenDouble.Parse(expected), actual);
            }
        }
    }

    private static void AssertPoints(string name, TempoGridCase golden, DerivedTempoGrid grid, double itemDuration)
    {
        foreach (var query in golden.Points)
        {
            var seconds = GoldenDouble.Parse(query.Seconds);
            Equal(
                name,
                $"nearestBeat({query.Seconds})",
                GoldenDouble.ParseOrNull(query.NearestBeat),
                grid.NearestBeat(seconds, itemDuration));
            Equal(
                name,
                $"nearestBar({query.Seconds})",
                GoldenDouble.ParseOrNull(query.NearestBar),
                grid.NearestBar(seconds, itemDuration));
        }
    }

    private static void Equal(string caseName, string what, double? expected, double? actual) =>
        Assert.True(
            GoldenDouble.BitwiseEquals(expected, actual),
            $"'{caseName}' {what}: expected {GoldenDouble.Describe(expected)}, got {GoldenDouble.Describe(actual)}");

    /// <summary>
    /// The vector carries <i>raw</i> cue values, so <see cref="Cue.Clamped"/> runs
    /// here — the same normalisation Swift's clamping <c>Cue.init</c> applies
    /// before the grid ever sees a cue. Pinning it at this seam means the vector
    /// covers both clamps, not just the grid's own.
    /// </summary>
    private static List<Cue> Cues(IReadOnlyList<TempoCueInput> inputs) =>
        inputs.Select(input => new Cue
        {
            Id = Guid.NewGuid(),
            Time = GoldenDouble.Parse(input.Time),
            Bpm = GoldenDouble.ParseOrNull(input.Bpm),
            BeatsPerBar = input.BeatsPerBar
        }.Clamped()).ToList();
}
