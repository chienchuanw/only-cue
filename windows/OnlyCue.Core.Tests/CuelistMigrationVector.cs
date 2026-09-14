using System.Text.Json.Nodes;
using System.Text.Json.Serialization;

namespace OnlyCue.Core.Tests;

/// <summary>
/// DTO mirroring <c>CuelistMigrationGoldenVector</c> in
/// <c>OnlyCueTests/CuelistMigrationGoldenVectorTests.swift</c>. macOS is the
/// source of truth for <c>golden/cuelist-migration-v1.json</c>; this side only
/// ever reads it.
/// </summary>
public sealed record CuelistMigrationVector(
    [property: JsonPropertyName("contract")] string Contract,
    [property: JsonPropertyName("version")] int Version,
    [property: JsonPropertyName("note")] string Note,
    [property: JsonPropertyName("cases")] IReadOnlyList<CuelistMigrationCase> Cases)
{
    private const string RelativePath = "golden/cuelist-migration-v1.json";

    public static CuelistMigrationVector Load() => GoldenFiles.Load<CuelistMigrationVector>(RelativePath);
}

public sealed record CuelistMigrationCase(
    [property: JsonPropertyName("name")] string Name,
    [property: JsonPropertyName("schemaVersion")] int SchemaVersion,
    /// <summary>The legacy document verbatim — the bytes a real file would carry.</summary>
    [property: JsonPropertyName("inputJSON")] string InputJson,
    /// <summary>The migrated current-schema model, with minted UUIDs replaced by
    /// <c>MINTED-000N</c> placeholders.</summary>
    [property: JsonPropertyName("expect")] JsonNode Expect);
