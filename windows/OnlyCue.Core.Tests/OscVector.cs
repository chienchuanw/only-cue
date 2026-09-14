using System.Text.Json.Serialization;

namespace OnlyCue.Core.Tests;

/// <summary>
/// DTO mirroring <c>OSCGoldenVector</c> in
/// <c>OnlyCueTests/OSCGoldenVectorTests.swift</c>. macOS is the source of truth
/// for <c>golden/osc-v1.json</c>; this side only ever reads it.
/// </summary>
public sealed record OscVector(
    [property: JsonPropertyName("contract")] string Contract,
    [property: JsonPropertyName("version")] int Version,
    [property: JsonPropertyName("note")] string Note,
    [property: JsonPropertyName("cases")] IReadOnlyList<OscCase> Cases)
{
    private const string RelativePath = "golden/osc-v1.json";

    public static OscVector Load() => GoldenFiles.Load<OscVector>(RelativePath);
}

/// <summary>One datagram, everything it parses to, and the command its first
/// message maps to. An empty <see cref="Messages"/> list is a real result — the
/// contract for malformed input — not a missing case.</summary>
public sealed record OscCase(
    [property: JsonPropertyName("name")] string Name,
    [property: JsonPropertyName("datagram")] string Datagram,
    [property: JsonPropertyName("messages")] IReadOnlyList<VectorOscMessage> Messages,
    [property: JsonPropertyName("command")] VectorOscCommand? Command);

public sealed record VectorOscMessage(
    [property: JsonPropertyName("address")] string Address,
    [property: JsonPropertyName("arguments")] IReadOnlyList<VectorOscArgument> Arguments);

/// <summary>A tagged union flattened for JSON: <c>type</c> selects which payload
/// field, if any, is present. Floats are carried as the exactly-widened double.</summary>
public sealed record VectorOscArgument(
    [property: JsonPropertyName("type")] string Type,
    [property: JsonPropertyName("int")] int? Int,
    [property: JsonPropertyName("float")] string? Float,
    [property: JsonPropertyName("text")] string? Text);

public sealed record VectorOscCommand(
    [property: JsonPropertyName("kind")] string Kind,
    [property: JsonPropertyName("seconds")] string? Seconds);
