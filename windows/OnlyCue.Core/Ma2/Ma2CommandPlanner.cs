using System.Globalization;
using OnlyCue.Core.Document;

namespace OnlyCue.Core.Ma2;

/// <summary>
/// Shared MA2 command-name quoting: names are wrapped in double quotes and there
/// is no documented escape for an embedded one, so strip them rather than break
/// the command. Mirrors Swift <c>MA2CommandQuoting</c>.
/// </summary>
public static class Ma2CommandQuoting
{
    public static string Quotable(string name) => name.Replace("\"", string.Empty);
}

/// <summary>
/// Pure planner for the telnet-command push (#683, Approach A): a media item's
/// filtered cues → the exact ordered command list that rebuilds the target
/// sequence as <c>Trig=Timecode</c> / <c>TrigTime</c> cues. Mirrors Swift
/// <c>MA2CommandPlanner</c> (<c>OnlyCue/MA2/MA2CommandPlanner.swift</c>);
/// <c>golden/ma2-telnet-v1.json</c> pins every string.
/// </summary>
public static class Ma2CommandPlanner
{
    /// <summary>
    /// The scalars Swift's <c>Character.isNewline</c> recognises.
    /// </summary>
    /// <remarks>
    /// Swift treats CRLF as a <i>single</i> Character, which would seem to need
    /// grapheme-level splitting here — but the split discards empty entries, so a
    /// CR/LF pair collapses to the same one separator either way.
    /// </remarks>
    private static readonly char[] NewlineCharacters =
        ['\n', '\r', '\u000B', '\u000C', '\u0085', '\u2028', '\u2029'];

    public static List<string> Commands(
        IReadOnlyList<Cue> cues,
        Ma2PushTarget target,
        string sequenceName,
        int startTimecodeFrames,
        SmpteFramerate framerate)
    {
        var seq = target.SequenceSlot.ToString(CultureInfo.InvariantCulture);
        var ordered = Ma2CueOrdering.ByNumber(cues);

        var commands = new List<string> { $"Delete Sequence {seq} /nc" };

        foreach (var cue in ordered)
        {
            var num = Ma2CueNumber.CommandString(cue.CueNumber ?? 0);
            var name = Ma2CommandQuoting.Quotable(cue.Name);
            commands.Add($"Store Sequence {seq} Cue {num} \"{name}\" /nc");
            commands.Add($"Assign Sequence {seq} Cue {num} /Trig=Timecode");

            var trig = Ma2TrigTime.Command(cue.Time, startTimecodeFrames, framerate);
            commands.Add($"Assign Sequence {seq} Cue {num} /TrigTime={trig}");

            if (cue.FadeTime.FadeIn > 0)
            {
                var fade = FadeTimeFormatting.FormatNumber(cue.FadeTime.FadeIn);
                commands.Add($"Assign Sequence {seq} Cue {num} /fade={fade}");
            }

            if (cue.FadeTime.FadeOut > 0)
            {
                var outfade = FadeTimeFormatting.FormatNumber(cue.FadeTime.FadeOut);
                commands.Add($"Assign Sequence {seq} Cue {num} /outfade={outfade}");
            }

            if (cue.Notes.Length > 0)
            {
                // Newlines would split the CRLF-framed telnet line; quotes would
                // break the quoted argument. Collapse to one line, strip quotes.
                var info = Ma2CommandQuoting.Quotable(
                    string.Join(' ', cue.Notes.Split(NewlineCharacters, StringSplitOptions.RemoveEmptyEntries)));
                commands.Add($"Assign Sequence {seq} Cue {num} /info=\"{info}\"");
            }
        }

        commands.Add($"Label Sequence {seq} \"{Ma2CommandQuoting.Quotable(sequenceName)}\"");

        // Executor is optional (#764): with none assigned, the sequence is left
        // in the pool for the operator to place — skip `At Exec` entirely.
        if (target.Executor is { } executor)
        {
            commands.Add($"Assign Sequence {seq} At Exec {executor.Page}.{executor.Number}");
        }

        return commands;
    }
}
