namespace OnlyCue.Core.Planning;

/// <summary>
/// grandMA2's cue-numbering window. Mirrors the bounds and the
/// <c>isInDomain</c> predicate on Swift <c>CueNumberValidator</c>
/// (<c>OnlyCue/Commands/CueNumberValidator.swift</c>).
/// </summary>
/// <remarks>
/// <para>
/// Only the window is ported. The rest of <c>CueNumberValidator</c> — duplicate
/// detection, the time-neighbour ordering rule, the error vocabulary — belongs to
/// the editing UI and has no C# caller yet.
/// </para>
/// <para>
/// Range and finiteness only, deliberately weaker than Swift's
/// <c>isWellFormatted</c>, which additionally demands the three-decimal
/// round-trip. Every boundary that <i>coerces</i> an untrusted number rather
/// than rejecting typed input gates on this window alone: a fourth decimal place
/// is rounded harmlessly into thousandths by both MA2 generators, whereas a
/// value outside the window has no MA2 meaning and misformats or traps
/// downstream (#830).
/// </para>
/// <para>
/// <c>IsFinite</c> is stated rather than relied upon: IEEE comparison already
/// rejects NaN and both infinities through the bounds alone, and dropping it
/// fails no test on either core (verified by mutation here and on the Swift
/// original). It stays so the two read alike, and because reordering the bounds
/// or folding them into <c>Math.Clamp</c> would silently change the non-finite
/// answer.
/// </para>
/// </remarks>
public static class CueNumberDomain
{
    /// <summary>Smallest legal MA2 cue number.</summary>
    public const double Minimum = 0.001;

    /// <summary>Largest legal MA2 cue number.</summary>
    public const double Maximum = 9999.999;

    public static bool IsInDomain(double value) =>
        double.IsFinite(value) && value >= Minimum && value <= Maximum;
}
