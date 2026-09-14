using OnlyCue.Core.Document;

namespace OnlyCue.Core.Planning;

/// <summary>
/// Picks the cue number for a newly inserted cue. A line-for-line
/// re-implementation of the Swift <c>CueNumberAssignment</c>
/// (<c>OnlyCue/Commands/CueNumberAssignment.swift</c>), kept in lockstep by the
/// golden-vector contract (<c>golden/cue-numbering-v1.json</c>, epic #728 M1b).
/// </summary>
public static class CueNumberAssignment
{
    /// <summary>
    /// Existing cues' numbers are never shifted — the rule produces a fractional
    /// value when needed so the new cue slots between its time-neighbours.
    /// Unnumbered cues are skipped when picking neighbours; the rule only
    /// considers cues that already carry a number.
    /// </summary>
    public static double Next(double time, IReadOnlyList<Cue> cues)
    {
        var numbered = cues
            .Where(cue => cue.CueNumber.HasValue)
            .Select(cue => (Time: cue.Time, Number: cue.CueNumber!.Value))
            .ToList();

        if (numbered.Count == 0)
        {
            return 1.0;
        }

        var earlier = LatestByTime(numbered.Where(entry => entry.Time <= time));
        var later = EarliestByTime(numbered.Where(entry => entry.Time > time));

        return (earlier, later) switch
        {
            (null, { } next) => next.Number - 1.0,
            ({ } previous, null) => previous.Number + 1.0,
            ({ } previous, { } next) => (previous.Number + next.Number) / 2.0,
            _ => throw new InvalidOperationException(
                $"CueNumberAssignment.Next: numbered cues non-empty but neither neighbour found at time {time}")
        };
    }

    // Swift's `max(by:)` / `min(by:)` replace the running result only on a
    // *strict* improvement, so an equal-time tie keeps the FIRST candidate.
    // Written as an explicit fold rather than LINQ's MaxBy/MinBy so that
    // tie-breaking is visible in the code rather than inherited from a library
    // guarantee that would be easy to lose in a refactor.

    private static (double Time, double Number)? LatestByTime(IEnumerable<(double Time, double Number)> entries)
    {
        (double Time, double Number)? best = null;
        foreach (var entry in entries)
        {
            if (best is null || best.Value.Time < entry.Time)
            {
                best = entry;
            }
        }

        return best;
    }

    private static (double Time, double Number)? EarliestByTime(IEnumerable<(double Time, double Number)> entries)
    {
        (double Time, double Number)? best = null;
        foreach (var entry in entries)
        {
            if (best is null || entry.Time < best.Value.Time)
            {
                best = entry;
            }
        }

        return best;
    }
}
