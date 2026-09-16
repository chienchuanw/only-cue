namespace OnlyCue.Core.Presentation;

/// <summary>
/// Resolves a Shift-click into the inclusive run of rows between the anchor and
/// the clicked row (#790). Mirrors Swift <c>CueRangeSelection</c>
/// (<c>OnlyCue/UI/CueRangeSelection.swift</c>).
/// </summary>
/// <remarks>
/// The range is resolved against the <b>displayed</b> id order the pane hands in,
/// never against the id or the cue time: the user is pointing at rows on screen,
/// so "between" can only mean between them as drawn. That also means a future
/// row-hiding filter needs no change here — only a shorter list.
/// </remarks>
public static class CueRangeSelection
{
    /// <param name="displayed">Every row id in the order it is drawn.</param>
    /// <param name="anchor">The last row selected <i>without</i> Shift.
    /// <c>null</c> before the first such click. An anchor that is no longer
    /// displayed — filtered out, or deleted from another pane — must not range
    /// from a phantom position.</param>
    /// <param name="target">The clicked row.</param>
    /// <returns>The inclusive range, or just <paramref name="target"/> when there
    /// is no usable anchor. The click has to do something, and selecting what was
    /// clicked is the only answer that does not surprise.</returns>
    public static IReadOnlySet<Guid> Range(IReadOnlyList<Guid> displayed, Guid? anchor, Guid target)
    {
        ArgumentNullException.ThrowIfNull(displayed);

        if (anchor is not { } origin)
        {
            return new HashSet<Guid> { target };
        }

        // `IndexOf` on an arbitrary IReadOnlyList is not in the BCL, so walk it —
        // and walk it once per end rather than materialising a lookup, since a cue
        // list is a few hundred rows and this runs on a click.
        var anchorIndex = IndexOf(displayed, origin);
        var targetIndex = IndexOf(displayed, target);
        if (anchorIndex < 0 || targetIndex < 0)
        {
            return new HashSet<Guid> { target };
        }

        var lower = Math.Min(anchorIndex, targetIndex);
        var upper = Math.Max(anchorIndex, targetIndex);
        var selected = new HashSet<Guid>();
        for (var index = lower; index <= upper; index++)
        {
            selected.Add(displayed[index]);
        }

        return selected;
    }

    private static int IndexOf(IReadOnlyList<Guid> displayed, Guid value)
    {
        for (var index = 0; index < displayed.Count; index++)
        {
            if (displayed[index] == value)
            {
                return index;
            }
        }

        return -1;
    }
}
