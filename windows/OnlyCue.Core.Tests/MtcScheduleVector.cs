using System.Text.Json.Serialization;

namespace OnlyCue.Core.Tests;

/// <summary>
/// DTO mirroring <c>MTCScheduleGoldenVector</c> in
/// <c>OnlyCueTests/MTCScheduleGolden.swift</c>. macOS is the source of truth for
/// <c>golden/mtc-schedule-v1.json</c>; this side only ever reads it.
/// </summary>
public sealed record MtcScheduleVector(
    [property: JsonPropertyName("contract")] string Contract,
    [property: JsonPropertyName("version")] int Version,
    [property: JsonPropertyName("note")] string Note,
    [property: JsonPropertyName("cases")] IReadOnlyList<MtcScheduleCase> Cases)
{
    private const string RelativePath = "golden/mtc-schedule-v1.json";

    public static MtcScheduleVector Load() => GoldenFiles.Load<MtcScheduleVector>(RelativePath);
}

public sealed record MtcScheduleCase(
    [property: JsonPropertyName("label")] string Label,
    [property: JsonPropertyName("op")] string Op,
    [property: JsonPropertyName("rate")] string Rate,
    [property: JsonPropertyName("input")] MtcScheduleInput Input,
    [property: JsonPropertyName("expect")] MtcScheduleExpect Expect);

public sealed record MtcScheduleInput(
    [property: JsonPropertyName("hours")] int? Hours,
    [property: JsonPropertyName("minutes")] int? Minutes,
    [property: JsonPropertyName("seconds")] int? Seconds,
    [property: JsonPropertyName("frames")] int? Frames,
    [property: JsonPropertyName("anchorHostTime")] ulong? AnchorHostTime,
    [property: JsonPropertyName("ticksPerSecond")] string? TicksPerSecond,
    [property: JsonPropertyName("sequenceIndex")] int? SequenceIndex,
    [property: JsonPropertyName("quarterFrameIndex")] int? QuarterFrameIndex,
    [property: JsonPropertyName("from")] ulong? From,
    [property: JsonPropertyName("until")] ulong? Until,
    [property: JsonPropertyName("boundaries")] IReadOnlyList<ulong>? Boundaries);

public sealed record MtcScheduleExpect(
    // op: "cadence"
    [property: JsonPropertyName("ticksPerQuarterFrame")] string? TicksPerQuarterFrame,
    // op: "sequenceTimecode"
    [property: JsonPropertyName("timecode")] string? Timecode,
    // op: "quarterFrame"
    [property: JsonPropertyName("byte")] int? Byte,
    [property: JsonPropertyName("timestamp")] ulong? Timestamp,
    // op: "batch" — [[byte, timestamp], …]
    [property: JsonPropertyName("messages")] IReadOnlyList<IReadOnlyList<ulong>>? Messages,
    // op: "batchChain"
    [property: JsonPropertyName("windows")] IReadOnlyList<IReadOnlyList<IReadOnlyList<ulong>>>? Windows,
    [property: JsonPropertyName("combined")] IReadOnlyList<IReadOnlyList<ulong>>? Combined);
