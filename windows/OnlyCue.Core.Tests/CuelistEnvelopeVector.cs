using System.Text.Json.Serialization;

namespace OnlyCue.Core.Tests;

/// <summary>
/// DTO mirroring <c>CuelistEnvelopeGoldenVector</c> in
/// <c>OnlyCueTests/CuelistEnvelopeGoldenVectorTests.swift</c>. macOS is the source
/// of truth for <c>golden/cuelist-envelope-v1.json</c>; this side only ever reads it.
/// </summary>
public sealed record CuelistEnvelopeVector(
    [property: JsonPropertyName("contract")] string Contract,
    [property: JsonPropertyName("version")] int Version,
    [property: JsonPropertyName("note")] string Note,
    [property: JsonPropertyName("cases")] IReadOnlyList<CuelistEnvelopeCase> Cases)
{
    private const string RelativePath = "golden/cuelist-envelope-v1.json";

    public static CuelistEnvelopeVector Load() =>
        GoldenFiles.Load<CuelistEnvelopeVector>(RelativePath);
}

public sealed record CuelistEnvelopeCase(
    [property: JsonPropertyName("name")] string Name,
    [property: JsonPropertyName("magic")] string Magic,
    [property: JsonPropertyName("allowLegacyPlaintext")] bool AllowLegacyPlaintext,
    [property: JsonPropertyName("inputBase64")] string InputBase64,
    [property: JsonPropertyName("expect")] CuelistEnvelopeExpect Expect);

public sealed record CuelistEnvelopeExpect(
    [property: JsonPropertyName("ok")] bool Ok,
    [property: JsonPropertyName("outputBase64")] string? OutputBase64,
    [property: JsonPropertyName("error")] string? Error);
