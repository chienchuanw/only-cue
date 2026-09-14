using OnlyCue.Core.Document;

namespace OnlyCue.Core.Ma2;

/// <summary>
/// The two cue orders every MA2 generator depends on. Extracted so the sequence
/// XML, the timecode XML and the telnet planner cannot drift apart on the rule
/// that makes them consistent: the sequence is <b>number</b>-ordered and the
/// timecode events are <b>time</b>-ordered, with each event carrying its cue's
/// number-ordered index.
/// </summary>
/// <remarks>
/// Swift sorts with <c>sorted(by:)</c>, which is documented as <b>not</b>
/// guaranteed stable, while LINQ's <c>OrderBy</c> is. That difference is only
/// observable on equal keys, so <c>golden/ma2-telnet-v1.json</c> and
/// <c>golden/ma2-export-v1.json</c> give every case distinct keys and the
/// contract records tie order as <i>unspecified</i> rather than pretending to pin
/// it. Do not add a vector case with duplicate cue numbers or times without
/// first deciding — on both platforms — what the tie should mean.
/// </remarks>
public static class Ma2CueOrdering
{
    /// <summary>MA2 sequences are number-ordered. An unnumbered cue sorts as 0,
    /// exactly as Swift's <c>($0.cueNumber ?? 0)</c> does.</summary>
    public static List<Cue> ByNumber(IReadOnlyList<Cue> cues) =>
        cues.OrderBy(cue => cue.CueNumber ?? 0).ToList();

    public static List<Cue> ByTime(IReadOnlyList<Cue> cues) =>
        cues.OrderBy(cue => cue.Time).ToList();

    /// <summary>Maps each cue id to its 1-based position in number order — the
    /// third <c>&lt;No&gt;</c> of a timecode event's cue reference.</summary>
    public static Dictionary<Guid, int> SequenceIndexByCueId(IReadOnlyList<Cue> cues)
    {
        var ordered = ByNumber(cues);
        var map = new Dictionary<Guid, int>(ordered.Count);
        for (var position = 0; position < ordered.Count; position++)
        {
            map[ordered[position].Id] = position + 1;
        }

        return map;
    }
}
