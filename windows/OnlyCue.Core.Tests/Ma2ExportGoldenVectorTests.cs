using OnlyCue.Core.Ma2;
using Xunit;

namespace OnlyCue.Core.Tests;

/// <summary>
/// The Windows half of the grandMA2 export contract (epic #728, M1c — vector 5).
/// macOS emits <c>golden/ma2-export-v1.json</c> from <c>MA2PushPlanner</c> and
/// <c>MA2PluginGenerator</c>; this suite asserts the C# re-implementation
/// reproduces all four artifacts byte for byte.
/// </summary>
public class Ma2ExportGoldenVectorTests
{
    private static readonly Ma2ExportVector Vector = Ma2ExportVector.Load();

    public static TheoryData<string> CaseNames => Names(Vector.Cases.Select(c => c.Name));

    [Fact]
    public void GoldenFile_IsTheExpectedContract()
    {
        Assert.Equal("ma2-export", Vector.Contract);
        Assert.Equal(1, Vector.Version);
        Assert.NotEmpty(Vector.Cases);
    }

    [Theory]
    [MemberData(nameof(CaseNames))]
    public void Export_ReproducesGoldenCase(string name)
    {
        var golden = Vector.Cases.Single(c => c.Name == name);
        var cues = Ma2VectorInput.Cues(golden.Cues);

        var plan = Ma2PushPlanner.Plan(cues, Ma2VectorInput.Target(golden.Target), new Ma2PushRequest
        {
            SequenceName = golden.SequenceName,
            TimecodeName = golden.TimecodeName,
            StartTimecodeFrames = golden.StartTimecodeFrames,
            LengthFrames = golden.LengthFrames,
            Framerate = Ma2VectorInput.Framerate(golden.Framerate),
            Showfile = golden.Showfile,
            Datetime = golden.Datetime
        });
        var bundle = Ma2PluginGenerator.Bundle(plan, golden.PluginName, golden.Datetime);

        var expected = golden.Expect;
        Assert.Equal(expected.SequenceFilename, plan.SequenceUpload.Filename);
        Assert.Equal(expected.TimecodeFilename, plan.TimecodeUpload.Filename);
        Assert.Equal(expected.LuaFilename, bundle.LuaFilename);
        Assert.Equal(expected.ManifestFilename, bundle.ManifestFilename);

        AssertArtifact($"'{name}' sequence xml", expected.SequenceXml, plan.SequenceUpload.Xml);
        AssertArtifact($"'{name}' timecode xml", expected.TimecodeXml, plan.TimecodeUpload.Xml);
        AssertArtifact($"'{name}' lua", expected.Lua, bundle.Lua);
        AssertArtifact($"'{name}' manifest xml", expected.ManifestXml, bundle.ManifestXml);

        Ma2TelnetGoldenVectorTests.AssertLines($"'{name}' commands", expected.Commands, plan.Commands);
    }

    /// <summary>
    /// Splits the generated artifact the same way the Swift generator did
    /// (<c>components(separatedBy: "\n")</c>) so a mismatch reports one line
    /// rather than a multi-kilobyte blob, then re-checks the joined form to prove
    /// the line transport itself is lossless.
    /// </summary>
    private static void AssertArtifact(string label, IReadOnlyList<string> expectedLines, string actual)
    {
        Ma2TelnetGoldenVectorTests.AssertLines(label, expectedLines, actual.Split('\n'));
        Assert.Equal(string.Join('\n', expectedLines), actual);
    }

    private static TheoryData<string> Names(IEnumerable<string> names)
    {
        var data = new TheoryData<string>();
        foreach (var name in names)
        {
            data.Add(name);
        }

        return data;
    }
}
