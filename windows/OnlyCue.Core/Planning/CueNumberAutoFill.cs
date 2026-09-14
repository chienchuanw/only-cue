using OnlyCue.Core.Document;

namespace OnlyCue.Core.Planning;

/// <summary>
/// Fills only the <c>null</c> cue numbers of a cue list so a grandMA2 push always
/// has a unique, ordered number per cue. User-entered numbers are never changed:
/// each gap is filled integer-first (<c>[1, _, 3]</c> → <c>2</c>), falling back to
/// a fractional step from the lower bound when no whole number fits
/// (<c>[1, _, 2]</c> → <c>1.1</c>). Cues are processed in time order and each
/// assigned value becomes the lower bound of the next, so consecutive gaps stay
/// strictly increasing and never collide with existing numbers.
/// </summary>
/// <remarks>
/// A line-for-line re-implementation of the Swift <c>CueNumberAutoFill</c>
/// (<c>OnlyCue/Commands/CueNumberAutoFill.swift</c>), kept in lockstep by the
/// golden-vector contract (<c>golden/cue-numbering-v1.json</c>, epic #728 M1b).
///
/// Two details are load-bearing and easy to lose in translation:
/// <list type="bullet">
/// <item>Every rounding here is round-half-<b>away-from-zero</b>, matching Swift's
/// <c>.rounded()</c>. .NET's parameterless <c>Math.Round</c> is banker's rounding
/// and picks a different thousandth on exact midpoints.</item>
/// <item>The time sort tie-breaks on the cue's <i>original index</i>. Swift needs
/// that because <c>Array.sorted(by:)</c> is not a specified-stable sort; the same
/// explicit tie-break is reproduced here rather than leaning on
/// <c>OrderBy</c>'s stability, so the two cores agree by construction.</item>
/// </list>
/// </remarks>
public static class CueNumberAutoFill
{
    /// <summary>Smallest legal MA2 cue number.</summary>
    private const double MinNumber = 0.001;

    /// <summary>
    /// <c>cue.Id</c> → assigned number, for the null-numbered cues only. Numbered
    /// cues and an empty list produce no entries. A null-numbered cue can also be
    /// absent: when the interval around it holds no unique thousandth, it is left
    /// unassigned for the MA2 pre-flight to report rather than given a duplicate.
    /// </summary>
    public static IReadOnlyDictionary<Guid, double> Assignments(IReadOnlyList<Cue> cues)
    {
        // Stable time order (original index breaks time ties).
        var ordered = cues
            .Select((cue, index) => (Cue: cue, Index: index))
            .OrderBy(entry => entry, TimeThenIndex)
            .Select(entry => entry.Cue)
            .ToList();

        // Seed the used set (integer-thousandths, matching the pre-flight's rounding).
        var used = new HashSet<int>(
            ordered.Where(cue => cue.CueNumber.HasValue).Select(cue => Key(cue.CueNumber!.Value)));

        // Upper bound for each slot = nearest *existing* number strictly after it.
        var nextExisting = new double?[ordered.Count];
        double? running = null;
        for (var index = ordered.Count - 1; index >= 0; index--)
        {
            nextExisting[index] = running;
            if (ordered[index].CueNumber is { } number)
            {
                running = number;
            }
        }

        var result = new Dictionary<Guid, double>();
        double? lower = null;  // nearest number before this slot (existing or just-assigned)
        for (var index = 0; index < ordered.Count; index++)
        {
            var cue = ordered[index];
            if (cue.CueNumber is { } existing)
            {
                lower = existing;
                continue;
            }

            if (Pick(lower, nextExisting[index], used) is not { } value)
            {
                continue;
            }

            result[cue.Id] = value;
            lower = value;
        }

        return result;
    }

    private static readonly IComparer<(Cue Cue, int Index)> TimeThenIndex =
        Comparer<(Cue Cue, int Index)>.Create((lhs, rhs) =>
            lhs.Cue.Time == rhs.Cue.Time
                ? lhs.Index.CompareTo(rhs.Index)
                : lhs.Cue.Time.CompareTo(rhs.Cue.Time));

    private static int Key(double number) => (int)Math.Round(number * 1000, MidpointRounding.AwayFromZero);

    private static double Round3(double number) => Math.Round(number * 1000, MidpointRounding.AwayFromZero) / 1000;

    /// <summary>
    /// First free, legal number strictly between <paramref name="lower"/> and
    /// <paramref name="upper"/> (either may be open), preferring whole numbers,
    /// then a <c>+0.1</c> step from the lower bound, then a binary-subdivision
    /// fallback for a tight upper bound. Returns <c>null</c> when the interval
    /// holds no unique thousandth ≥ <see cref="MinNumber"/> — every candidate is
    /// validated by <c>Fits</c>, so the result can never duplicate an existing
    /// number or fall out of range.
    /// </summary>
    private static double? Pick(double? lower, double? upper, HashSet<int> used)
    {
        var baseValue = lower ?? 0;

        bool Fits(double value) =>
            value >= MinNumber
            && value > baseValue
            && (upper is not { } bound || value < bound)
            && !used.Contains(Key(value));

        double Take(double value)
        {
            used.Add(Key(value));
            return value;
        }

        // Cue numbers are always positive, so floor(lower)+1 >= 1 (and 1 when open).
        var candidate = lower is { } start ? (int)Math.Floor(start) + 1 : 1;
        while (upper is not { } ceiling || candidate < ceiling)
        {
            if (Fits(candidate))
            {
                return Take(candidate);
            }

            candidate += 1;
        }

        // +0.1 steps from the lower bound (upper is non-null here — the integer scan
        // above never exits for an open upper).
        var step = 1;
        while (upper is { } bound && Round3(baseValue + (step * 0.1)) < bound)
        {
            var value = Round3(baseValue + (step * 0.1));
            if (Fits(value))
            {
                return Take(value);
            }

            step += 1;
        }

        // Tight bound: subdivide (base, upper) looking for a free thousandth.
        if (upper is not { } high)
        {
            return null;
        }

        for (var attempt = 0; attempt < 40; attempt++)
        {
            var mid = Round3((baseValue + high) / 2);
            if (Fits(mid))
            {
                return Take(mid);
            }

            if (high - baseValue < MinNumber)
            {
                break;  // gap narrower than the thousandths grid
            }

            high = mid;
        }

        return null;
    }
}
