using System.Text.Json.Serialization;

namespace OnlyCue.Core.Tests;

/// <summary>
/// DTO mirroring <c>MTCWireGoldenVector</c> in
/// <c>OnlyCueTests/MTCWireGolden.swift</c>. macOS is the source of truth for
/// <c>golden/mtc-wire-v1.json</c>; this side only ever reads it.
/// </summary>
public sealed record MtcWireVector(
    [property: JsonPropertyName("contract")] string Contract,
    [property: JsonPropertyName("version")] int Version,
    [property: JsonPropertyName("note")] string Note,
    [property: JsonPropertyName("cases")] IReadOnlyList<MtcWireCase> Cases)
{
    private const string RelativePath = "golden/mtc-wire-v1.json";

    public static MtcWireVector Load() => GoldenFiles.Load<MtcWireVector>(RelativePath);
}

public sealed record MtcWireCase(
    [property: JsonPropertyName("label")] string Label,
    [property: JsonPropertyName("op")] string Op,
    [property: JsonPropertyName("rate")] string Rate,
    [property: JsonPropertyName("input")] MtcWireInput Input,
    [property: JsonPropertyName("expect")] MtcWireExpect Expect);

/// <summary>Every field is optional: the <c>rateBits</c> cases carry no timecode
/// at all, and only the clamp cases carry a piece index.</summary>
public sealed record MtcWireInput(
    [property: JsonPropertyName("hours")] int? Hours,
    [property: JsonPropertyName("minutes")] int? Minutes,
    [property: JsonPropertyName("seconds")] int? Seconds,
    [property: JsonPropertyName("frames")] int? Frames,
    [property: JsonPropertyName("piece")] int? Piece);

public sealed record MtcWireExpect(
    // op: "rateBits" | "quarterFrame"
    [property: JsonPropertyName("byte")] int? Byte,
    // op: "quarterFrameSequence" | "fullFrame"
    [property: JsonPropertyName("bytes")] IReadOnlyList<int>? Bytes);
