using System.Globalization;
using OnlyCue.Core.Document;

namespace OnlyCue.Core.Ma2;

/// <summary>
/// The ordered grandMA2 push plan (#683): two XML files to FTP into
/// <c>gma2/importexport/</c> and the telnet command list that rebuilds the target
/// sequence / timecode slots from them. Mirrors Swift <c>MA2PushPlan</c>.
/// </summary>
public sealed record Ma2PushPlan(
    Ma2PushPlan.Upload SequenceUpload,
    Ma2PushPlan.Upload TimecodeUpload,
    IReadOnlyList<string> Commands)
{
    /// <param name="Filename">File name inside <c>gma2/importexport/</c>
    /// (slot-stamped, <c>.xml</c>).</param>
    public sealed record Upload(string Filename, string Xml);
}

/// <summary>
/// The inputs to <see cref="Ma2PushPlanner.Plan"/>. A parameter object for the
/// same reason as <see cref="Ma2TimecodeXmlRequest"/>: the Swift original needs a
/// <c>function_parameter_count</c> lint waiver, and several of the parameters are
/// interchangeable <c>int</c>s and <c>string</c>s that a positional call could
/// silently swap.
/// </summary>
public sealed record Ma2PushRequest
{
    public required string SequenceName { get; init; }

    public required string TimecodeName { get; init; }

    public required int StartTimecodeFrames { get; init; }

    public required int LengthFrames { get; init; }

    public required SmpteFramerate Framerate { get; init; }

    public required string Showfile { get; init; }

    /// <summary>A caller-supplied literal, never a live clock — the contract
    /// requires the generators to be pure so the vector can pin them.</summary>
    public required string Datetime { get; init; }
}

/// <summary>
/// Pure planner — generates the XML payloads and the exact telnet command
/// strings. Mirrors Swift <c>MA2PushPlanner</c>
/// (<c>OnlyCue/MA2/MA2PushPlanner.swift</c>).
/// </summary>
public static class Ma2PushPlanner
{
    public static Ma2PushPlan Plan(IReadOnlyList<Cue> cues, Ma2PushTarget target, Ma2PushRequest request)
    {
        var sequenceSlot = target.SequenceSlot.ToString(CultureInfo.InvariantCulture);
        var timecodeSlot = target.TimecodeSlot.ToString(CultureInfo.InvariantCulture);
        var sequenceFileBase = $"onlycue_seq_{sequenceSlot}";
        var timecodeFileBase = $"onlycue_tc_{timecodeSlot}";

        var sequenceUpload = new Ma2PushPlan.Upload(
            $"{sequenceFileBase}.xml",
            Ma2SequenceXmlGenerator.Xml(cues, request.SequenceName, request.Showfile, request.Datetime));

        var timecodeUpload = new Ma2PushPlan.Upload(
            $"{timecodeFileBase}.xml",
            Ma2TimecodeXmlGenerator.Xml(cues, new Ma2TimecodeXmlRequest
            {
                TimecodeSlot = target.TimecodeSlot,
                TimecodeName = request.TimecodeName,
                SequenceSlot = target.SequenceSlot,
                SequenceName = request.SequenceName,
                ExecutorPage = target.ExecutorPage,
                ExecutorNumber = target.ExecutorNumber,
                Command = target.TimecodeCommand,
                StartTimecodeFrames = request.StartTimecodeFrames,
                LengthFrames = request.LengthFrames,
                Framerate = request.Framerate,
                Showfile = request.Showfile,
                Datetime = request.Datetime
            }));

        // Delete x2 first (idempotent rebuild), sequence import from inside the
        // sequence pool directory (`Import … At` argument order is flipped vs
        // Export — wrong order gives Error #12), back to root, timecode import,
        // executor assign, labels.
        var commands = new List<string>
        {
            $"Delete Sequence {sequenceSlot} /nc",
            $"Delete Timecode {timecodeSlot} /nc",
            "cd Sequences",
            "cd Global",
            $"Import \"{sequenceFileBase}\" At {sequenceSlot} /nc",
            "cd /",
            $"Import \"{timecodeFileBase}\" At Timecode {timecodeSlot} /nc"
        };

        // Executor is optional (#764): skip the assign when unassigned.
        if (target.Executor is { } executor)
        {
            commands.Add($"Assign Sequence {sequenceSlot} At Exec {executor.Page}.{executor.Number}");
        }

        commands.Add($"Label Sequence {sequenceSlot} \"{Ma2CommandQuoting.Quotable(request.SequenceName)}\"");
        commands.Add($"Label Timecode {timecodeSlot} \"{Ma2CommandQuoting.Quotable(request.TimecodeName)}\"");

        return new Ma2PushPlan(sequenceUpload, timecodeUpload, commands);
    }
}
