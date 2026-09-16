using System.Text.Json.Serialization;

namespace OnlyCue.Core.Tests;

/// <summary>
/// DTO mirroring <c>LTCWireGoldenVector</c> in
/// <c>OnlyCueTests/LTCWireGolden.swift</c>. macOS is the source of truth for
/// <c>golden/ltc-wire-v1.json</c>; this side only ever reads it.
/// </summary>
public sealed record LtcWireVector(
    [property: JsonPropertyName("contract")] string Contract,
    [property: JsonPropertyName("version")] int Version,
    [property: JsonPropertyName("note")] string Note,
    [property: JsonPropertyName("cases")] IReadOnlyList<LtcWireCase> Cases)
{
    private const string RelativePath = "golden/ltc-wire-v1.json";

    public static LtcWireVector Load() => GoldenFiles.Load<LtcWireVector>(RelativePath);
}

public sealed record LtcWireCase(
    [property: JsonPropertyName("label")] string Label,
    [property: JsonPropertyName("op")] string Op,
    [property: JsonPropertyName("rate")] string Rate,
    [property: JsonPropertyName("input")] LtcWireInput Input,
    [property: JsonPropertyName("expect")] LtcWireExpect Expect);

public sealed record LtcWireInput(
    [property: JsonPropertyName("hours")] int Hours,
    [property: JsonPropertyName("minutes")] int Minutes,
    [property: JsonPropertyName("seconds")] int Seconds,
    [property: JsonPropertyName("frames")] int Frames,
    [property: JsonPropertyName("sampleRate")] string? SampleRate,
    [property: JsonPropertyName("amplitude")] string? Amplitude,
    [property: JsonPropertyName("startLevel")] bool? StartLevel);

public sealed record LtcWireExpect(
    // op: "frame"
    [property: JsonPropertyName("bits")] string? Bits,
    [property: JsonPropertyName("parityBitIndex")] int? ParityBitIndex,
    [property: JsonPropertyName("parityBit")] bool? ParityBit,
    [property: JsonPropertyName("bit27")] bool? Bit27,
    [property: JsonPropertyName("bit59")] bool? Bit59,
    [property: JsonPropertyName("hasEvenParity")] bool? HasEvenParity,
    [property: JsonPropertyName("syncWordIsValid")] bool? SyncWordIsValid,
    // op: "encode"
    [property: JsonPropertyName("totalSamples")] int? TotalSamples,
    [property: JsonPropertyName("endLevel")] bool? EndLevel,
    [property: JsonPropertyName("runs")] IReadOnlyList<IReadOnlyList<int>>? Runs);
