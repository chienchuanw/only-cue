namespace OnlyCue.Core.Presentation;

/// <summary>
/// Which of the four fills a cue row lands on, named rather than rendered.
/// Mirrors Swift <c>CueRowFill.Resolution</c>.
/// </summary>
/// <remarks>
/// The precedence is the contract, and two branches produce the <i>same</i>
/// colour: <see cref="Current"/> and <see cref="SelectionFallback"/> both paint
/// the achromatic selection highlight. So a colour-level comparison cannot
/// distinguish this from an implementation that tested selection before current —
/// which would hide the playhead's cue whenever a different row was selected.
/// Naming the four outcomes is what lets the vector pin the order (#837).
/// </remarks>
public enum CueRowFillResolution
{
    /// <summary>The cue at the playhead — the achromatic selection highlight.</summary>
    Current,

    /// <summary>The selected row's own cue-type tint (the reserved chroma).</summary>
    Tint,

    /// <summary>Selected but with no type colour: the achromatic highlight again.</summary>
    SelectionFallback,

    /// <summary>Idle row — no fill.</summary>
    Clear
}

/// <summary>
/// Resolves a cue row's background fill. Mirrors Swift <c>CueRowFill</c>
/// (<c>OnlyCue/UI/CueRowFill.swift</c>). Only the decision is ported; spelling it
/// in a brush stays with each platform's view layer.
/// </summary>
public static class CueRowFill
{
    /// <param name="isSelected">The row is in the list selection.</param>
    /// <param name="isCurrent">The cue is the one at the playhead.</param>
    /// <param name="hasTint">The cue resolves to a type colour.</param>
    /// <remarks>
    /// The current-cue highlight takes precedence over the manual selection tint,
    /// so the playhead's cue stays visible even when another row is selected for
    /// editing (#671). A selected cue with no type colour falls back to the
    /// achromatic highlight so it stays visible (#679) — otherwise it would render
    /// as <see cref="CueRowFillResolution.Clear"/>.
    /// </remarks>
    public static CueRowFillResolution Resolution(bool isSelected, bool isCurrent, bool hasTint)
    {
        if (isCurrent)
        {
            return CueRowFillResolution.Current;
        }

        if (!isSelected)
        {
            return CueRowFillResolution.Clear;
        }

        return hasTint ? CueRowFillResolution.Tint : CueRowFillResolution.SelectionFallback;
    }
}
