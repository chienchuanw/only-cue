using System.Text.Json.Serialization;

namespace OnlyCue.Core.Tests;

/// <summary>
/// DTO mirroring <c>TempoGridGoldenVector</c> in
/// <c>OnlyCueTests/TempoGridGoldenVectorTests.swift</c>. macOS is the source of
/// truth for <c>golden/tempo-grid-v1.json</c>; this side only ever reads it.
/// </summary>
public sealed record TempoGridVector(
    [property: JsonPropertyName("contract")] string Contract,
    [property: JsonPropertyName("version")] int Version,
    [property: JsonPropertyName("note")] string Note,
    [property: JsonPropertyName("cases")] IReadOnlyList<TempoGridCase> Cases)
{
    private const string RelativePath = "golden/tempo-grid-v1.json";

    public static TempoGridVector Load() => GoldenFiles.Load<TempoGridVector>(RelativePath);
}

public sealed record TempoGridCase(
    [property: JsonPropertyName("name")] string Name,
    [property: JsonPropertyName("cues")] IReadOnlyList<TempoCueInput> Cues,
    [property: JsonPropertyName("itemDuration")] string ItemDuration,
    [property: JsonPropertyName("segments")] IReadOnlyList<SegmentOutput> Segments,
    [property: JsonPropertyName("ranges")] IReadOnlyList<RangeQuery> Ranges,
    [property: JsonPropertyName("points")] IReadOnlyList<PointQuery> Points);

/// <summary>Raw cue input — the clamping that Swift's <c>Cue.init</c> performs has
/// deliberately <i>not</i> been applied, so the verifier must call
/// <c>Cue.Clamped()</c> and thereby pin that step too.</summary>
public sealed record TempoCueInput(
    [property: JsonPropertyName("time")] string Time,
    [property: JsonPropertyName("bpm")] string? Bpm,
    [property: JsonPropertyName("beatsPerBar")] int? BeatsPerBar);

public sealed record SegmentOutput(
    [property: JsonPropertyName("startSeconds")] string StartSeconds,
    [property: JsonPropertyName("bpm")] string Bpm,
    [property: JsonPropertyName("beatsPerBar")] int BeatsPerBar,
    [property: JsonPropertyName("beatDuration")] string BeatDuration,
    [property: JsonPropertyName("barDuration")] string BarDuration);

public sealed record VectorBeat(
    [property: JsonPropertyName("time")] string Time,
    [property: JsonPropertyName("isDownbeat")] bool IsDownbeat);

public sealed record RangeQuery(
    [property: JsonPropertyName("lowerBound")] string LowerBound,
    [property: JsonPropertyName("upperBound")] string UpperBound,
    [property: JsonPropertyName("beats")] IReadOnlyList<VectorBeat> Beats,
    [property: JsonPropertyName("bars")] IReadOnlyList<string> Bars);

public sealed record PointQuery(
    [property: JsonPropertyName("seconds")] string Seconds,
    [property: JsonPropertyName("nearestBeat")] string? NearestBeat,
    [property: JsonPropertyName("nearestBar")] string? NearestBar);
