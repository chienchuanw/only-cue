using System.Globalization;
using OnlyCue.Core.Document;

namespace OnlyCue.Core.Ma2;

/// <summary>
/// The inputs to <see cref="Ma2TimecodeXmlGenerator.Xml"/>. A parameter object
/// because the generator needs thirteen of them and a positional call would be
/// unreadable — and, worse, silently mis-orderable between the four
/// interchangeable <c>int</c>s (two slots, two executor fields).
/// </summary>
public sealed record Ma2TimecodeXmlRequest
{
    public required int TimecodeSlot { get; init; }

    public required string TimecodeName { get; init; }

    public required int SequenceSlot { get; init; }

    public required string SequenceName { get; init; }

    public int? ExecutorPage { get; init; }

    public int? ExecutorNumber { get; init; }

    public required Ma2TimecodeCommand Command { get; init; }

    public required int StartTimecodeFrames { get; init; }

    public required int LengthFrames { get; init; }

    public required SmpteFramerate Framerate { get; init; }

    public required string Showfile { get; init; }

    public required string Datetime { get; init; }
}

/// <summary>
/// Generates the grandMA2 timecode-show import XML (#683): one Go/Goto event per
/// cue on the chosen executor, times in <b>frames</b> at the project SMPTE
/// framerate, offset by the clip's start timecode. Mirrors Swift
/// <c>MA2TimecodeXMLGenerator</c>.
/// </summary>
public static class Ma2TimecodeXmlGenerator
{
    public static string Xml(IReadOnlyList<Cue> cues, Ma2TimecodeXmlRequest request)
    {
        // The sequence import is number-ordered; the third <No> of each event's
        // cue reference is that number-sorted 1-based index. Events themselves
        // run in time order — cue numbers need not be monotonic with time, and
        // golden/ma2-export-v1.json has a case where the two orders disagree so
        // this cross-wiring is actually pinned.
        var sequenceIndexByCueId = Ma2CueOrdering.SequenceIndexByCueId(cues);
        var timeOrdered = Ma2CueOrdering.ByTime(cues);

        var escape = Ma2SequenceXmlGenerator.Escape;
        var fps = request.Framerate.FramesPerSecond();

        var lines = new List<string>
        {
            "<?xml version=\"1.0\" encoding=\"utf-8\"?>",
            "<?xml-stylesheet type=\"text/xsl\" href=\"styles/timecode@sheet.xsl\"?>",
            "<MA xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" "
                + "xmlns=\"http://schemas.malighting.de/grandma2/xml/MA\" "
                + "xsi:schemaLocation=\"http://schemas.malighting.de/grandma2/xml/MA "
                + "http://schemas.malighting.de/grandma2/xml/3.9.60/MA.xsd\" "
                + "major_vers=\"3\" minor_vers=\"9\" stream_vers=\"60\">",
            $"\t<Info datetime=\"{escape(request.Datetime)}\" showfile=\"{escape(request.Showfile)}\" />",

            // `lenght` (sic) is MA2's real attribute spelling — not a typo to fix.
            // The TC-slot link (which LTC input drives the show) is left for the
            // operator: imports without a `slot` attribute keep the pool default.
            $"\t<Timecode index=\"{Int(request.TimecodeSlot - 1)}\" name=\"{escape(request.TimecodeName)}\" "
                + $"lenght=\"{Int(request.LengthFrames)}\" play_mode=\"Play\" "
                + $"frame_format=\"{Int(fps)} FPS\">",
            "\t\t<Track index=\"0\" active=\"true\" expanded=\"true\">"
        };

        // The track object is the executor: object path 30/1/page/exec; the name
        // attribute is cosmetic ("SequName page.exec" in real exports). Executor
        // is optional (#764) — an unassigned target emits no executor Object.
        if ((request.ExecutorPage, request.ExecutorNumber) is ({ } page, { } exec))
        {
            lines.Add($"\t\t\t<Object name=\"{escape(request.SequenceName)} {Int(page)}.{Int(exec)}\">");
            foreach (var number in new[] { 30, 1, page, exec })
            {
                lines.Add($"\t\t\t\t<No>{Int(number)}</No>");
            }

            lines.Add("\t\t\t</Object>");
        }

        lines.Add("\t\t\t<SubTrack index=\"0\">");
        for (var eventIndex = 0; eventIndex < timeOrdered.Count; eventIndex++)
        {
            var cue = timeOrdered[eventIndex];
            lines.AddRange(EventElement(
                cue,
                eventIndex,
                sequenceIndexByCueId.TryGetValue(cue.Id, out var index) ? index : 0,
                request));
        }

        lines.Add("\t\t\t</SubTrack>");
        lines.Add("\t\t</Track>");
        lines.Add("\t</Timecode>");
        lines.Add("</MA>");
        return string.Join('\n', lines);
    }

    private static List<string> EventElement(
        Cue cue,
        int eventIndex,
        int sequenceIndex,
        Ma2TimecodeXmlRequest request)
    {
        // For 30df this emits *physical* frame counts under a non-drop "30 FPS"
        // format label (MA2 has no drop-frame format); how the console maps them
        // when chasing DF LTC is a rig-validation item (#683 plan step 13).
        //
        // AwayFromZero matches Swift's `.rounded()`; banker's rounding would put
        // a cue landing on an exact half-frame one frame early.
        var frame = request.StartTimecodeFrames
            + (int)Math.Round(cue.Time * request.Framerate.FramesPerSecond(), MidpointRounding.AwayFromZero);

        var attributes = new List<string> { $"index=\"{Int(eventIndex)}\"" };
        if (frame != 0)
        {
            // Real exports omit `time` at frame 0.
            attributes.Add($"time=\"{Int(frame)}\"");
        }

        attributes.Add($"command=\"{CommandKeyword(request.Command)}\"");
        attributes.Add("pressed=\"true\"");
        attributes.Add($"step=\"{Int(eventIndex + 1)}\"");

        var cueName = cue.Name.Length == 0
            ? string.Empty
            : $" name=\"{Ma2SequenceXmlGenerator.Escape(cue.Name)}\"";

        var lines = new List<string>
        {
            $"\t\t\t\t<Event {string.Join(' ', attributes)}>",
            $"\t\t\t\t\t<Cue{cueName}>"
        };

        // Cue reference object path: 1 = sequence object type, then the sequence
        // pool slot, then the number-sorted cue index within it.
        foreach (var number in new[] { 1, request.SequenceSlot, sequenceIndex })
        {
            lines.Add($"\t\t\t\t\t\t<No>{Int(number)}</No>");
        }

        lines.Add("\t\t\t\t\t</Cue>");
        lines.Add("\t\t\t\t</Event>");
        return lines;
    }

    /// <summary>XML wants the MA keyword casing (<c>Go</c> / <c>Goto</c>), not the
    /// persisted lowercase raw value.</summary>
    private static string CommandKeyword(Ma2TimecodeCommand command) => command switch
    {
        Ma2TimecodeCommand.Go => "Go",
        Ma2TimecodeCommand.Goto => "Goto",
        _ => throw new ArgumentOutOfRangeException(nameof(command))
    };

    private static string Int(int value) => value.ToString(CultureInfo.InvariantCulture);
}
