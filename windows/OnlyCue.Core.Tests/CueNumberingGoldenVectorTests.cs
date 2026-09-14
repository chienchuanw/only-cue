using OnlyCue.Core.Document;
using OnlyCue.Core.Planning;
using Xunit;

namespace OnlyCue.Core.Tests;

/// <summary>
/// The Windows half of the cue-numbering contract (epic #728, M1b — vector 3).
/// macOS emits <c>golden/cue-numbering-v1.json</c> from the Swift
/// <c>CueNumberAssignment</c> / <c>CueNumberAutoFill</c>; this suite asserts the
/// C# re-implementation reproduces every case bit-for-bit, so drift between the
/// two hand-maintained cores fails CI instead of shipping.
/// </summary>
public class CueNumberingGoldenVectorTests
{
    private static readonly CueNumberingVector Vector = CueNumberingVector.Load();

    public static TheoryData<string> InsertionNames => Names(Vector.Insertion.Select(c => c.Name));

    public static TheoryData<string> AutoFillNames => Names(Vector.AutoFill.Select(c => c.Name));

    [Fact]
    public void GoldenFile_IsTheExpectedContract()
    {
        Assert.Equal("cue-numbering", Vector.Contract);
        Assert.Equal(1, Vector.Version);
        Assert.NotEmpty(Vector.Insertion);
        Assert.NotEmpty(Vector.AutoFill);
    }

    [Theory]
    [MemberData(nameof(InsertionNames))]
    public void Insertion_ReproducesGoldenCase(string name)
    {
        var golden = Vector.Insertion.Single(c => c.Name == name);
        var expected = GoldenDouble.Parse(golden.Expect);

        var actual = CueNumberAssignment.Next(GoldenDouble.Parse(golden.AtTime), Cues(golden.Cues));

        Assert.True(
            GoldenDouble.BitwiseEquals(expected, actual),
            $"insertion '{name}': expected {GoldenDouble.Describe(expected)}, got {GoldenDouble.Describe(actual)}");
    }

    [Theory]
    [MemberData(nameof(AutoFillNames))]
    public void AutoFill_ReproducesGoldenCase(string name)
    {
        var golden = Vector.AutoFill.Single(c => c.Name == name);
        var cues = Cues(golden.Cues);

        var assigned = CueNumberAutoFill.Assignments(cues);

        // Compare by input index, which is how the vector identifies cues.
        var actual = cues
            .Select((cue, index) => (Index: index, Number: assigned.TryGetValue(cue.Id, out var n) ? n : (double?)null))
            .Where(entry => entry.Number.HasValue)
            .ToList();
        var expected = golden.Expect
            .Select(entry => (entry.Index, Number: (double?)GoldenDouble.Parse(entry.Number)))
            .ToList();

        Assert.True(
            actual.Count == expected.Count,
            $"auto-fill '{name}': expected {expected.Count} assignment(s) at "
            + $"[{string.Join(", ", expected.Select(e => e.Index))}], got {actual.Count} at "
            + $"[{string.Join(", ", actual.Select(a => a.Index))}]");

        foreach (var (expectedEntry, actualEntry) in expected.Zip(actual))
        {
            Assert.True(
                expectedEntry.Index == actualEntry.Index,
                $"auto-fill '{name}': expected an assignment at index {expectedEntry.Index}, got {actualEntry.Index}");
            Assert.True(
                GoldenDouble.BitwiseEquals(expectedEntry.Number, actualEntry.Number),
                $"auto-fill '{name}' index {expectedEntry.Index}: expected "
                + $"{GoldenDouble.Describe(expectedEntry.Number)}, got {GoldenDouble.Describe(actualEntry.Number)}");
        }
    }

    /// <summary>
    /// Deterministic identifiers so a case's cues map back to their input index
    /// without the vector carrying any. Matches the Swift generator's scheme, but
    /// nothing depends on that — only on uniqueness within a case.
    /// </summary>
    private static List<Cue> Cues(IReadOnlyList<VectorCueInput> inputs) =>
        inputs.Select((input, index) => new Cue
        {
            Id = Identifier(index),
            TypeId = Identifier(0),
            CueNumber = GoldenDouble.ParseOrNull(input.CueNumber),
            Time = GoldenDouble.Parse(input.Time)
        }).ToList();

    private static Guid Identifier(int index) =>
        new([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, (byte)(index >> 8), (byte)(index & 0xFF)]);

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
