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
/// Both orders are <b>total</b>: equal keys fall back to the cue's position in
/// the input. LINQ's <c>OrderBy</c> is stable and Swift's <c>sorted(by:)</c>
/// happens to be, but Swift documents its sort as <b>not</b> guaranteed stable,
/// so before #834 the tie order was an implementation detail the two platforms
/// only coincidentally agreed on. Ties are the normal case rather than an edge
/// one — every cue created through <c>CueCommands</c> starts unnumbered and
/// <c>?? 0</c> collapses all of them onto the same key — so
/// <c>golden/ma2-telnet-v1.json</c> and <c>golden/ma2-export-v1.json</c> each
/// carry a case with duplicate keys.
///
/// The fallback is the input position rather than <c>Cue.Id</c> on purpose: a
/// .NET <c>Guid</c> and a Swift <c>UUID</c> do not order the same way
/// (<c>Guid</c>'s first three fields are little-endian), so tie-breaking on the
/// identifier would have replaced an unspecified order with a reliably
/// <i>different</i> one on the two platforms.
///
/// On this side the <c>ThenBy</c> is documentary rather than load-bearing:
/// <c>OrderBy</c> is documented stable, so removing it leaves all 548 tests
/// green. It stays so both files state the same rule in the same place — the
/// Swift half, where the stability guarantee does not exist, genuinely needs it.
/// </remarks>
public static class Ma2CueOrdering
{
    /// <summary>MA2 sequences are number-ordered. An unnumbered cue sorts as 0,
    /// exactly as Swift's <c>($0.cueNumber ?? 0)</c> does.</summary>
    public static List<Cue> ByNumber(IReadOnlyList<Cue> cues) =>
        Ordered(cues, cue => cue.CueNumber ?? 0);

    public static List<Cue> ByTime(IReadOnlyList<Cue> cues) =>
        Ordered(cues, cue => cue.Time);

    private static List<Cue> Ordered(IReadOnlyList<Cue> cues, Func<Cue, double> key) =>
        cues.Select((cue, index) => (cue, index))
            .OrderBy(entry => key(entry.cue))
            .ThenBy(entry => entry.index)
            .Select(entry => entry.cue)
            .ToList();

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
