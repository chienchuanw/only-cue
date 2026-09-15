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

/// <summary>What that click should do. Mirrors Swift <c>CueRowTapIntent</c>.</summary>
public enum CueRowTapIntent
{
    /// <summary>Select this row and put the caret in the tapped field. Never seeks.</summary>
    BeginEdit,

    /// <summary>Toggle this row's membership of the selection. Never edits, never seeks.</summary>
    ExtendSelection,

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
    /// <param name="isExtending">Whether a selection modifier was held. Holding one
    /// means "I am selecting, not typing".</param>
    /// <param name="isReadOnly">Show mode. The columns are disabled there, so they
    /// receive no taps at all; the stripe stays live because it is the only
    /// remaining way to jump the playhead from the cue list.</param>
    public static CueRowTapIntent Intent(CueRowTapTarget target, bool isExtending, bool isReadOnly) =>
        target switch
        {
            CueRowTapTarget.Field when isReadOnly => CueRowTapIntent.Ignored,
            CueRowTapTarget.Field => isExtending ? CueRowTapIntent.ExtendSelection : CueRowTapIntent.BeginEdit,
            CueRowTapTarget.Stripe => isExtending ? CueRowTapIntent.ExtendSelection : CueRowTapIntent.SelectAndSeek,
            // Spelled out rather than caught by a discard, so a future third target
            // has to choose an intent instead of silently inheriting the stripe's.
            _ => throw new ArgumentOutOfRangeException(nameof(target), target, "unknown tap target")
        };
}
