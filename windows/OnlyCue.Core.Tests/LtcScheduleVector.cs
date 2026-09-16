using System.Text.Json.Serialization;

namespace OnlyCue.Core.Tests;

/// <summary>
/// DTO mirroring <c>LTCScheduleGoldenVector</c> in
/// <c>OnlyCueTests/LTCScheduleGolden.swift</c>. macOS is the source of truth for
/// <c>golden/ltc-schedule-v1.json</c>; this side only ever reads it.
/// </summary>
public sealed record LtcScheduleVector(
    [property: JsonPropertyName("contract")] string Contract,
    [property: JsonPropertyName("version")] int Version,
    [property: JsonPropertyName("note")] string Note,
    [property: JsonPropertyName("cases")] IReadOnlyList<LtcScheduleCase> Cases)
{
    private const string RelativePath = "golden/ltc-schedule-v1.json";

    public static LtcScheduleVector Load() => GoldenFiles.Load<LtcScheduleVector>(RelativePath);
}

public sealed record LtcScheduleCase(
    [property: JsonPropertyName("label")] string Label,
    [property: JsonPropertyName("op")] string Op,
    [property: JsonPropertyName("rate")] string Rate,
    [property: JsonPropertyName("input")] LtcScheduleInput Input,
    [property: JsonPropertyName("expect")] LtcScheduleExpect Expect);

/// <summary>Run lengths around one frame join, and the sample index it sits at.</summary>
public sealed record LtcScheduleJoin(
    [property: JsonPropertyName("at")] int At,
    [property: JsonPropertyName("runs")] IReadOnlyList<IReadOnlyList<int>> Runs);

public sealed record LtcScheduleInput(
    [property: JsonPropertyName("hours")] int? Hours,
    [property: JsonPropertyName("minutes")] int? Minutes,
    [property: JsonPropertyName("seconds")] int? Seconds,
    [property: JsonPropertyName("frames")] int? Frames,
    [property: JsonPropertyName("sampleRate")] string? SampleRate,
    [property: JsonPropertyName("amplitude")] string? Amplitude,
    [property: JsonPropertyName("frameCount")] int? FrameCount,
    [property: JsonPropertyName("frameOffset")] int? FrameOffset,
    [property: JsonPropertyName("framesPerBuffer")] int? FramesPerBuffer,
    [property: JsonPropertyName("bufferIndex")] int? BufferIndex,
    [property: JsonPropertyName("elapsedSeconds")] string? ElapsedSeconds,
    [property: JsonPropertyName("leadBuffers")] int? LeadBuffers,
    [property: JsonPropertyName("targetSeconds")] string? TargetSeconds);

public sealed record LtcScheduleExpect(
    // op: "stream"
    [property: JsonPropertyName("samplesPerFrame")] int? SamplesPerFrame,
    [property: JsonPropertyName("totalSamples")] int? TotalSamples,
    [property: JsonPropertyName("firstSampleIsHigh")] bool? FirstSampleIsHigh,
    [property: JsonPropertyName("lastSampleIsHigh")] bool? LastSampleIsHigh,
    [property: JsonPropertyName("joins")] IReadOnlyList<LtcScheduleJoin>? Joins,
    // op: "streamTimecode" | "buffer"
    [property: JsonPropertyName("timecode")] string? Timecode,
    // op: "schedule"
    [property: JsonPropertyName("samplesPerBuffer")] int? SamplesPerBuffer,
    [property: JsonPropertyName("bufferDuration")] string? BufferDuration,
    // op: "buffer"
    [property: JsonPropertyName("sampleCount")] int? SampleCount,
    // op: "bufferSeam"
    [property: JsonPropertyName("previousEndsHigh")] bool? PreviousEndsHigh,
    [property: JsonPropertyName("nextStartsHigh")] bool? NextStartsHigh,
    [property: JsonPropertyName("runs")] IReadOnlyList<IReadOnlyList<int>>? Runs,
    // op: "targetBufferCount"
    [property: JsonPropertyName("count")] int? Count,
    // op: "framesPerBuffer"
    [property: JsonPropertyName("frames")] int? Frames);
