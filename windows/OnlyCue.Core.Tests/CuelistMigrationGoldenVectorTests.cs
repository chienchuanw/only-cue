using System.Text.Json.Nodes;
using OnlyCue.Core.Document;
using Xunit;

namespace OnlyCue.Core.Tests;

/// <summary>
/// The Windows half of the schema-ladder contract (epic #728, M1a). macOS emits
/// <c>golden/cuelist-migration-v1.json</c> — one representative document per
/// schema version, paired with the current-schema model the Swift ladder
/// produces — and this suite asserts the C# re-implementation lands on the same
/// model for every one of them.
/// </summary>
public class CuelistMigrationGoldenVectorTests
{
    private static readonly CuelistMigrationVector Vector = CuelistMigrationVector.Load();

    public static TheoryData<string> CaseNames
    {
        get
        {
            var data = new TheoryData<string>();
            foreach (var name in Vector.Cases.Select(c => c.Name))
            {
                data.Add(name);
            }

            return data;
        }
    }

    [Fact]
    public void GoldenFile_IsTheExpectedContract()
    {
        Assert.Equal("cuelist-migration", Vector.Contract);
        Assert.Equal(1, Vector.Version);
        Assert.NotEmpty(Vector.Cases);
    }

    /// <summary>
    /// Every rung must be represented. A gap here is how a version quietly stops
    /// being covered as the schema grows — and since macOS writes the file, the
    /// gap would appear on this side as silence rather than as a failure.
    /// </summary>
    [Fact]
    public void Vector_CoversEverySchemaVersion()
    {
        Assert.Equal(
            Enumerable.Range(1, ProjectModel.CurrentSchemaVersion).ToArray(),
            Vector.Cases.Select(c => c.SchemaVersion).ToArray());
    }

    /// <summary>
    /// The version this core believes is current must be the one macOS generated
    /// against. If macOS bumps the schema and this constant lags, every other
    /// assertion here would still pass while the port silently wrote documents
    /// stamped with the wrong version.
    /// </summary>
    [Fact]
    public void CurrentSchemaVersion_MatchesTheVector()
    {
        Assert.Equal(ProjectModel.CurrentSchemaVersion, Vector.Cases.Max(c => c.SchemaVersion));
    }

    [Theory]
    [MemberData(nameof(CaseNames))]
    public void CSharpCore_ReproducesGoldenCase(string name)
    {
        var goldenCase = Vector.Cases.Single(c => c.Name == name);

        var migrated = ProjectModelCodec.Decode(goldenCase.InputJson);
        Assert.Equal(ProjectModel.CurrentSchemaVersion, migrated.SchemaVersion);

        var actual = JsonNode.Parse(ProjectModelCodec.Encode(migrated));
        var differences = MigratedModelComparer.Differences(goldenCase.Expect, actual, goldenCase.InputJson);

        Assert.True(
            differences.Count == 0,
            $"{name} diverged from golden/cuelist-migration-v1.json:{Environment.NewLine}"
            + string.Join(Environment.NewLine, differences.Select(line => "  " + line)));
    }

    /// <summary>
    /// The comparer's placeholder binding is only trustworthy if a literal id it
    /// should have carried through cannot pass as a minted one. This feeds it a
    /// deliberately wrong answer — the carried id where the vector expects a
    /// fresh one — and requires a complaint.
    /// </summary>
    [Fact]
    public void Comparer_RejectsACarriedIdWhereAMintedOneIsExpected()
    {
        const string carried = "11111111-1111-1111-1111-111111111111";
        var differences = MigratedModelComparer.Differences(
            JsonNode.Parse($"{{\"id\":\"MINTED-0001\"}}"),
            JsonNode.Parse($"{{\"id\":\"{carried}\"}}"),
            $"{{\"cues\":[{{\"id\":\"{carried}\"}}]}}");

        Assert.Single(differences);
        Assert.Contains("carried from the input", differences[0], StringComparison.Ordinal);
    }

    /// <summary>
    /// …and only trustworthy if one placeholder cannot stand for two different
    /// ids. v1 relies on this: its <c>MINTED-0001</c> is both the media item's
    /// <c>id</c> and the project's <c>activeItemID</c>, so a rung that minted
    /// those separately would still produce the right <i>shape</i>.
    /// </summary>
    [Fact]
    public void Comparer_RejectsOnePlaceholderStandingForTwoIds()
    {
        var differences = MigratedModelComparer.Differences(
            JsonNode.Parse("{\"a\":\"MINTED-0001\",\"b\":\"MINTED-0001\"}"),
            JsonNode.Parse(
                "{\"a\":\"AAAAAAAA-0000-0000-0000-000000000001\",\"b\":\"BBBBBBBB-0000-0000-0000-000000000002\"}"),
            "{}");

        Assert.Single(differences);
        Assert.Contains("already bound to", differences[0], StringComparison.Ordinal);
    }

    /// <summary>
    /// A document stamped with a version no rung handles must fail loudly rather
    /// than load as an empty show — the Windows-side equivalent of Swift's
    /// <c>LoadError.unsupportedSchemaVersion</c>.
    /// </summary>
    [Fact]
    public void Decode_RejectsAnUnknownSchemaVersion()
    {
        var future = ProjectModel.CurrentSchemaVersion + 1;
        var thrown = Assert.Throws<UnsupportedSchemaVersionException>(
            () => ProjectModelCodec.Decode($"{{\"schemaVersion\":{future}}}"));

        Assert.Equal(future, thrown.SchemaVersion);
    }

    /// <summary>
    /// A current-schema document must survive a decode → encode → decode round
    /// trip unchanged. The golden cases only prove the <i>migrations</i> agree
    /// with macOS; this proves this core does not perturb a document it merely
    /// opened and saved.
    /// </summary>
    [Theory]
    [MemberData(nameof(CaseNames))]
    public void Encode_IsStableAcrossARoundTrip(string name)
    {
        var goldenCase = Vector.Cases.Single(c => c.Name == name);

        var once = ProjectModelCodec.Encode(ProjectModelCodec.Decode(goldenCase.InputJson));
        var twice = ProjectModelCodec.Encode(ProjectModelCodec.Decode(once));

        Assert.Equal(once, twice);
    }
}
