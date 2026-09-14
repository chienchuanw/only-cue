using System.Text.Json.Serialization;
using OnlyCue.Core;
using OnlyCue.Core.Document;

namespace OnlyCue.Core.Tests;

/// <summary>
/// DTOs mirroring <c>MA2TelnetGoldenVector</c> and <c>MA2ExportGoldenVector</c>
/// (<c>OnlyCueTests/Support/MA2GoldenVectorModel.swift</c> and the two generator
/// test files). macOS is the source of truth for <c>golden/ma2-telnet-v1.json</c>
/// and <c>golden/ma2-export-v1.json</c>; this side only ever reads them.
/// </summary>
public sealed record Ma2TelnetVector(
    [property: JsonPropertyName("contract")] string Contract,
    [property: JsonPropertyName("version")] int Version,
    [property: JsonPropertyName("note")] string Note,
    [property: JsonPropertyName("plans")] IReadOnlyList<Ma2PlanCase> Plans,
    [property: JsonPropertyName("trigTimes")] IReadOnlyList<Ma2TrigTimeCase> TrigTimes,
    [property: JsonPropertyName("cueNumbers")] IReadOnlyList<Ma2CueNumberCase> CueNumbers,
    [property: JsonPropertyName("names")] IReadOnlyList<Ma2NameCase> Names)
{
    public static Ma2TelnetVector Load() => GoldenFiles.Load<Ma2TelnetVector>("golden/ma2-telnet-v1.json");
}

public sealed record Ma2ExportVector(
    [property: JsonPropertyName("contract")] string Contract,
    [property: JsonPropertyName("version")] int Version,
    [property: JsonPropertyName("note")] string Note,
    [property: JsonPropertyName("cases")] IReadOnlyList<Ma2ExportCase> Cases)
{
    public static Ma2ExportVector Load() => GoldenFiles.Load<Ma2ExportVector>("golden/ma2-export-v1.json");
}

/// <summary>Only the fields the MA2 generators read. Cues are identified by
/// position, so the vector mints no identifiers.</summary>
public sealed record Ma2CueInput(
    [property: JsonPropertyName("cueNumber")] string? CueNumber,
    [property: JsonPropertyName("name")] string Name,
    [property: JsonPropertyName("time")] string Time,
    [property: JsonPropertyName("notes")] string Notes,
    [property: JsonPropertyName("fadeIn")] string FadeIn,
    [property: JsonPropertyName("fadeOut")] string FadeOut);

public sealed record Ma2TargetInput(
    [property: JsonPropertyName("sequenceSlot")] int SequenceSlot,
    [property: JsonPropertyName("timecodeSlot")] int TimecodeSlot,
    [property: JsonPropertyName("executorPage")] int? ExecutorPage,
    [property: JsonPropertyName("executorNumber")] int? ExecutorNumber,
    [property: JsonPropertyName("timecodeCommand")] string TimecodeCommand);

public sealed record Ma2PlanCase(
    [property: JsonPropertyName("name")] string Name,
    [property: JsonPropertyName("cues")] IReadOnlyList<Ma2CueInput> Cues,
    [property: JsonPropertyName("target")] Ma2TargetInput Target,
    [property: JsonPropertyName("sequenceName")] string SequenceName,
    [property: JsonPropertyName("startTimecodeFrames")] int StartTimecodeFrames,
    [property: JsonPropertyName("framerate")] string Framerate,
    [property: JsonPropertyName("expect")] IReadOnlyList<string> Expect);

public sealed record Ma2TrigTimeCase(
    [property: JsonPropertyName("name")] string Name,
    [property: JsonPropertyName("cueTime")] string CueTime,
    [property: JsonPropertyName("startTimecodeFrames")] int StartTimecodeFrames,
    [property: JsonPropertyName("framerate")] string Framerate,
    [property: JsonPropertyName("expectSeconds")] string ExpectSeconds,
    [property: JsonPropertyName("expectCommand")] string ExpectCommand);

public sealed record Ma2CueNumberCase(
    [property: JsonPropertyName("name")] string Name,
    [property: JsonPropertyName("value")] string Value,
    [property: JsonPropertyName("expectNumber")] int ExpectNumber,
    [property: JsonPropertyName("expectSubNumber")] int ExpectSubNumber,
    [property: JsonPropertyName("expectCommandString")] string ExpectCommandString);

public sealed record Ma2NameCase(
    [property: JsonPropertyName("name")] string Name,
    [property: JsonPropertyName("raw")] string Raw,
    [property: JsonPropertyName("fallbackSlot")] int FallbackSlot,
    [property: JsonPropertyName("expect")] string Expect);

public sealed record Ma2ExportCase(
    [property: JsonPropertyName("name")] string Name,
    [property: JsonPropertyName("cues")] IReadOnlyList<Ma2CueInput> Cues,
    [property: JsonPropertyName("target")] Ma2TargetInput Target,
    [property: JsonPropertyName("sequenceName")] string SequenceName,
    [property: JsonPropertyName("timecodeName")] string TimecodeName,
    [property: JsonPropertyName("pluginName")] string PluginName,
    [property: JsonPropertyName("startTimecodeFrames")] int StartTimecodeFrames,
    [property: JsonPropertyName("lengthFrames")] int LengthFrames,
    [property: JsonPropertyName("framerate")] string Framerate,
    [property: JsonPropertyName("showfile")] string Showfile,
    [property: JsonPropertyName("datetime")] string Datetime,
    [property: JsonPropertyName("expect")] Ma2Artifacts Expect);

/// <summary>
/// Each artifact arrives as an array of lines rather than one escaped blob, so
/// the committed vector stays diff-reviewable. Rejoining with <c>"\n"</c>
/// reproduces the file exactly, including a trailing <c>\r</c> on CRLF content.
/// </summary>
public sealed record Ma2Artifacts(
    [property: JsonPropertyName("sequenceFilename")] string SequenceFilename,
    [property: JsonPropertyName("sequenceXML")] IReadOnlyList<string> SequenceXml,
    [property: JsonPropertyName("timecodeFilename")] string TimecodeFilename,
    [property: JsonPropertyName("timecodeXML")] IReadOnlyList<string> TimecodeXml,
    [property: JsonPropertyName("commands")] IReadOnlyList<string> Commands,
    [property: JsonPropertyName("luaFilename")] string LuaFilename,
    [property: JsonPropertyName("lua")] IReadOnlyList<string> Lua,
    [property: JsonPropertyName("manifestFilename")] string ManifestFilename,
    [property: JsonPropertyName("manifestXML")] IReadOnlyList<string> ManifestXml);

/// <summary>Rehydrates the vector's inputs into core types. Shared by both MA2
/// suites so they cannot disagree about what a case describes.</summary>
internal static class Ma2VectorInput
{
    public static List<Cue> Cues(IReadOnlyList<Ma2CueInput> inputs) =>
        inputs.Select((input, index) => new Cue
        {
            Id = Identifier(index),
            TypeId = Identifier(0),
            CueNumber = GoldenDouble.ParseOrNull(input.CueNumber),
            Name = input.Name,
            Time = GoldenDouble.Parse(input.Time),
            Notes = input.Notes,
            FadeTime = new FadeTime
            {
                FadeIn = GoldenDouble.Parse(input.FadeIn),
                FadeOut = GoldenDouble.Parse(input.FadeOut)
            }
        }).ToList();

    public static Ma2PushTarget Target(Ma2TargetInput input) => new()
    {
        SequenceSlot = input.SequenceSlot,
        TimecodeSlot = input.TimecodeSlot,
        ExecutorPage = input.ExecutorPage,
        ExecutorNumber = input.ExecutorNumber,
        TimecodeCommand = input.TimecodeCommand switch
        {
            "go" => Ma2TimecodeCommand.Go,
            "goto" => Ma2TimecodeCommand.Goto,
            _ => throw new InvalidDataException($"unknown timecode command '{input.TimecodeCommand}'")
        },
        IncludedTypeIds = []
    };

    public static SmpteFramerate Framerate(string rawValue) => SmpteFramerateExtensions.FromRawValue(rawValue);

    /// <summary>Deterministic identifiers so a case's cues map back to their input
    /// index without the vector carrying any. Matches the Swift generator's
    /// scheme, but nothing depends on that — only on uniqueness within a case.
    /// </summary>
    private static Guid Identifier(int index) =>
        new([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, (byte)(index >> 8), (byte)(index & 0xFF)]);
}
