using OnlyCue.Core.Document;
using OnlyCue.Core.Ma2;
using Xunit;

namespace OnlyCue.Core.Tests;

/// <summary>
/// The Windows half of the grandMA2 telnet contract (epic #728, M1c — vector 4).
/// macOS emits <c>golden/ma2-telnet-v1.json</c> from <c>MA2CommandPlanner</c> and
/// its three primitives; this suite asserts the C# re-implementation reproduces
/// every string exactly.
/// </summary>
/// <remarks>
/// Unlike vectors 3 and 7 the deliverable is <i>formatted text</i>, so a wrong
/// character is an <c>Error #</c> on a real console mid-show rather than a value
/// that is merely a little off. Every assertion below is on the literal string.
/// </remarks>
public class Ma2TelnetGoldenVectorTests
{
    private static readonly Ma2TelnetVector Vector = Ma2TelnetVector.Load();

    public static TheoryData<string> PlanNames => Names(Vector.Plans.Select(c => c.Name));

    public static TheoryData<string> TrigTimeNames => Names(Vector.TrigTimes.Select(c => c.Name));

    public static TheoryData<string> CueNumberNames => Names(Vector.CueNumbers.Select(c => c.Name));

    public static TheoryData<string> NameNames => Names(Vector.Names.Select(c => c.Name));

    [Fact]
    public void GoldenFile_IsTheExpectedContract()
    {
        Assert.Equal("ma2-telnet", Vector.Contract);
        Assert.Equal(1, Vector.Version);
        Assert.NotEmpty(Vector.Plans);
        Assert.NotEmpty(Vector.TrigTimes);
        Assert.NotEmpty(Vector.CueNumbers);
        Assert.NotEmpty(Vector.Names);
    }

    [Theory]
    [MemberData(nameof(PlanNames))]
    public void CommandPlan_ReproducesGoldenCase(string name)
    {
        var golden = Vector.Plans.Single(c => c.Name == name);

        var actual = Ma2CommandPlanner.Commands(
            Ma2VectorInput.Cues(golden.Cues),
            Ma2VectorInput.Target(golden.Target),
            golden.SequenceName,
            golden.StartTimecodeFrames,
            Ma2VectorInput.Framerate(golden.Framerate));

        AssertLines($"plan '{name}'", golden.Expect, actual);
    }

    [Theory]
    [MemberData(nameof(TrigTimeNames))]
    public void TrigTime_ReproducesGoldenCase(string name)
    {
        var golden = Vector.TrigTimes.Single(c => c.Name == name);
        var cueTime = GoldenDouble.Parse(golden.CueTime);
        var framerate = Ma2VectorInput.Framerate(golden.Framerate);

        var seconds = Ma2TrigTime.Seconds(cueTime, golden.StartTimecodeFrames, framerate);
        var expectedSeconds = GoldenDouble.Parse(golden.ExpectSeconds);

        Assert.True(
            GoldenDouble.BitwiseEquals(expectedSeconds, seconds),
            $"trig time '{name}': expected {GoldenDouble.Describe(expectedSeconds)}, "
            + $"got {GoldenDouble.Describe(seconds)}");

        Assert.Equal(
            golden.ExpectCommand,
            Ma2TrigTime.Command(cueTime, golden.StartTimecodeFrames, framerate));
    }

    [Theory]
    [MemberData(nameof(CueNumberNames))]
    public void CueNumber_ReproducesGoldenCase(string name)
    {
        var golden = Vector.CueNumbers.Single(c => c.Name == name);
        var value = GoldenDouble.Parse(golden.Value);

        var parts = Ma2CueNumber.Split(value);

        Assert.Equal((golden.ExpectNumber, golden.ExpectSubNumber), (parts.Number, parts.SubNumber));
        Assert.Equal(golden.ExpectCommandString, Ma2CueNumber.CommandString(value));
    }

    [Theory]
    [MemberData(nameof(NameNames))]
    public void Sanitize_ReproducesGoldenCase(string name)
    {
        var golden = Vector.Names.Single(c => c.Name == name);

        Assert.Equal(golden.Expect, Ma2Name.Sanitize(golden.Raw, golden.FallbackSlot));
    }

    /// <summary>
    /// Compares line by line and reports the first divergence with both sides
    /// quoted, because a whole-list <c>Assert.Equal</c> on twenty near-identical
    /// telnet commands is unreadable when it fails.
    /// </summary>
    internal static void AssertLines(string label, IReadOnlyList<string> expected, IReadOnlyList<string> actual)
    {
        foreach (var (index, pair) in expected.Zip(actual).Index())
        {
            Assert.True(
                pair.First == pair.Second,
                $"{label} line {index}:\n  expected: {pair.First}\n  actual:   {pair.Second}");
        }

        if (expected.Count == actual.Count)
        {
            return;
        }

        // Built only on the failing path: `Assert.True` evaluates its message
        // eagerly, and both indices below are out of range when the counts agree.
        Assert.Fail(
            $"{label}: expected {expected.Count} line(s), got {actual.Count}"
            + (actual.Count > expected.Count
                ? $"\n  first extra:   {actual[expected.Count]}"
                : $"\n  first missing: {expected[actual.Count]}"));
    }

    private static TheoryData<string> Names(IEnumerable<string> names)
    {
        var data = new TheoryData<string>();
        foreach (var name in names)
        {
            data.Add(name);
        }

        return data;
    }
}
