using System.Text.Json.Serialization;

namespace OnlyCue.Core.Tests;

/// <summary>
/// DTO mirroring <c>CueNumberingGoldenVector</c> in
/// <c>OnlyCueTests/CueNumberingGoldenVectorTests.swift</c>. macOS is the source of
/// truth for <c>golden/cue-numbering-v1.json</c>; this side only ever reads it.
/// </summary>
public sealed record CueNumberingVector(
    [property: JsonPropertyName("contract")] string Contract,
    [property: JsonPropertyName("version")] int Version,
    [property: JsonPropertyName("note")] string Note,
    [property: JsonPropertyName("insertion")] IReadOnlyList<InsertionCase> Insertion,
    [property: JsonPropertyName("autoFill")] IReadOnlyList<AutoFillCase> AutoFill)
{
    private const string RelativePath = "golden/cue-numbering-v1.json";

    public static CueNumberingVector Load() => GoldenFiles.Load<CueNumberingVector>(RelativePath);
}

/// <summary>The two fields either algorithm reads. Cues are identified by their
/// position in the case's array, so the vector mints no identifiers.</summary>
public sealed record VectorCueInput(
    [property: JsonPropertyName("time")] string Time,
    [property: JsonPropertyName("cueNumber")] string? CueNumber);

public sealed record InsertionCase(
    [property: JsonPropertyName("name")] string Name,
    [property: JsonPropertyName("cues")] IReadOnlyList<VectorCueInput> Cues,
    [property: JsonPropertyName("atTime")] string AtTime,
    [property: JsonPropertyName("expect")] string Expect);

public sealed record AutoFillCase(
    [property: JsonPropertyName("name")] string Name,
    [property: JsonPropertyName("cues")] IReadOnlyList<VectorCueInput> Cues,
    [property: JsonPropertyName("expect")] IReadOnlyList<VectorAssignment> Expect);

public sealed record VectorAssignment(
    [property: JsonPropertyName("index")] int Index,
    [property: JsonPropertyName("number")] string Number);
