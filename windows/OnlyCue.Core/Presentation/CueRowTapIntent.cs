namespace OnlyCue.Core.Presentation;

/// <summary>Which part of a cue row was clicked. Mirrors Swift
/// <c>CueRowTapTarget</c>.</summary>
public enum CueRowTapTarget
{
    /// <summary>One of the three text columns.</summary>
    Field,

    /// <summary>The leading cue-type colour stripe.</summary>
    Stripe
}

/// <summary>Which selection gesture the held modifiers name (#790). Mirrors Swift
/// <c>CueRowTapModifier</c>.</summary>
/// <remarks>
/// #786 read Ctrl/Cmd and Shift as one <c>isExtending</c> flag, which made a
/// Shift-click a toggle and left the list with no contiguous range selection at
/// all. They are two gestures, so they are two cases. Reading the platform's
/// modifier state into this enum is UI glue and stays out of the core — but the
/// precedence when both are held (Shift wins) is a decision, and it is pinned by
/// the macOS unit tests.
/// </remarks>
public enum CueRowTapModifier
{
    /// <summary>No selection modifier held.</summary>
    Plain,

    /// <summary>Add or remove this one row.</summary>
    Toggle,

    /// <summary>Select from the anchor to this row.</summary>
    Range
}

/// <summary>What that click should do. Mirrors Swift <c>CueRowTapIntent</c>.</summary>
public enum CueRowTapIntent
{
    /// <summary>Select this row and put the caret in the tapped field. Never seeks.</summary>
    BeginEdit,

    /// <summary>Toggle this row's membership of the selection. Never edits, never seeks.</summary>
    ToggleSelection,

    /// <summary>Select the rows between the anchor and this one, replacing the
    /// selection. Never edits, never seeks.</summary>
    ExtendRange,

    /// <summary>Select this row and move the playhead to its time.</summary>
    SelectAndSeek,

    Ignored
}

/// <summary>
/// What a single click on part of a cue row should do (#786). Mirrors Swift
/// <c>CueRowTap</c> (<c>OnlyCue/UI/CueRowTapIntent.swift</c>).
/// </summary>
/// <remarks>
/// A cue row is exactly three columns wide and they cover it end to end. Once a
/// plain click inside a column means "start typing here", the row has no mouse
/// path left to selection or to the playhead — so the leading cue-type colour
/// stripe takes that job and becomes the row's handle.
/// </remarks>
public static class CueRowTap
{
    /// <param name="modifier">Which selection gesture the click carries. Holding
    /// either selection modifier means "I am selecting, not typing".</param>
    /// <param name="isReadOnly">Show mode. The columns are disabled there, so they
    /// receive no taps at all; the stripe stays live because it is the only
    /// remaining way to jump the playhead from the cue list.</param>
    public static CueRowTapIntent Intent(CueRowTapTarget target, CueRowTapModifier modifier, bool isReadOnly) =>
        target switch
        {
            CueRowTapTarget.Field when isReadOnly => CueRowTapIntent.Ignored,
            CueRowTapTarget.Field => Selecting(modifier) ?? CueRowTapIntent.BeginEdit,
            CueRowTapTarget.Stripe => Selecting(modifier) ?? CueRowTapIntent.SelectAndSeek,
            // Spelled out rather than caught by a discard, so a future third target
            // has to choose an intent instead of silently inheriting the stripe's.
            _ => throw new ArgumentOutOfRangeException(nameof(target), target, "unknown tap target")
        };

    /// <summary>The intent both targets share, or <c>null</c> when no selection
    /// modifier is held and the target's own plain behaviour applies.</summary>
    private static CueRowTapIntent? Selecting(CueRowTapModifier modifier) => modifier switch
    {
        CueRowTapModifier.Plain => null,
        CueRowTapModifier.Toggle => CueRowTapIntent.ToggleSelection,
        CueRowTapModifier.Range => CueRowTapIntent.ExtendRange,
        _ => throw new ArgumentOutOfRangeException(nameof(modifier), modifier, "unknown tap modifier")
    };
}
