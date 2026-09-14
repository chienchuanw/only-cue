using System.Text.Json.Serialization;

namespace OnlyCue.Core.Tests;

/// <summary>
/// DTO mirroring <c>TimecodeGoldenVector</c> in
/// <c>OnlyCueTests/TimecodeGoldenVectorTests.swift</c>. macOS is the source of
/// truth for <c>golden/timecode-v1.json</c>; this side only ever reads it.
/// </summary>
public sealed record GoldenVector(
    [property: JsonPropertyName("contract")] string Contract,
    [property: JsonPropertyName("version")] int Version,
    [property: JsonPropertyName("note")] string Note,
    [property: JsonPropertyName("cases")] IReadOnlyList<GoldenCase> Cases)
{
    private const string RelativePath = "golden/timecode-v1.json";

    public static GoldenVector Load() => GoldenFiles.Load<GoldenVector>(RelativePath);
}

public sealed record GoldenCase(
    [property: JsonPropertyName("op")] string Op,
    [property: JsonPropertyName("rate")] string Rate,
    [property: JsonPropertyName("input")] GoldenInput Input,
    [property: JsonPropertyName("expect")] GoldenExpect Expect)
{
    /// <summary>A stable, human-readable label so a failing xUnit case names the
    /// exact vector rather than an index.</summary>
    public string Label => Op switch
    {
        "fromFrameCount" => $"{Op}@{Rate}(frameCount: {Input.FrameCount})",
        "fromTotalSeconds" => $"{Op}@{Rate}(totalSeconds: {Input.TotalSeconds})",
        "parse" => $"{Op}@{Rate}(\"{Input.String}\")",
        _ => $"{Op}@{Rate}"
    };
}

public sealed record GoldenInput(
    [property: JsonPropertyName("frameCount")] int? FrameCount,
    [property: JsonPropertyName("totalSeconds")] double? TotalSeconds,
    [property: JsonPropertyName("string")] string? String);

public sealed record GoldenExpect(
    [property: JsonPropertyName("valid")] bool Valid,
    [property: JsonPropertyName("hours")] int? Hours,
    [property: JsonPropertyName("minutes")] int? Minutes,
    [property: JsonPropertyName("seconds")] int? Seconds,
    [property: JsonPropertyName("frames")] int? Frames,
    [property: JsonPropertyName("display")] string? Display,
    [property: JsonPropertyName("frameCount")] int? FrameCount);
