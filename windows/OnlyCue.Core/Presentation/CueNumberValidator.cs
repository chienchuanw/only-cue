using OnlyCue.Core.Document;
using OnlyCue.Core.Planning;

namespace OnlyCue.Core.Presentation;

/// <summary>Which rule a cue-number assignment fell foul of. Mirrors the cases of
/// Swift <c>CueNumberValidator.Result</c>.</summary>
public enum CueNumberValidationKind
{
    Ok,
    InvalidFormat,
    Duplicate,
    OutOfRange
}

/// <summary>
/// The C# shape of Swift's <c>CueNumberValidator.Result</c>, whose
/// <c>outOfRange</c> case carries two optional bounds. Either bound is
/// <c>null</c> when the target cue has no numbered time-neighbour on that side.
/// </summary>
public readonly record struct CueNumberValidationResult(
    CueNumberValidationKind Kind,
    double? LowerExclusive,
    double? UpperExclusive)
{
    public static CueNumberValidationResult Ok => new(CueNumberValidationKind.Ok, null, null);

    public static CueNumberValidationResult InvalidFormat =>
        new(CueNumberValidationKind.InvalidFormat, null, null);

    public static CueNumberValidationResult Duplicate => new(CueNumberValidationKind.Duplicate, null, null);

    public static CueNumberValidationResult OutOfRange(double? lowerExclusive, double? upperExclusive) =>
        new(CueNumberValidationKind.OutOfRange, lowerExclusive, upperExclusive);
}

/// <summary>
/// grandMA2-shaped validation for cue-number assignments. Mirrors Swift
/// <c>CueNumberValidator</c> (<c>OnlyCue/Commands/CueNumberValidator.swift</c>),
/// pinned by <c>golden/cue-presentation-v1.json</c> (#837).
/// </summary>
/// <remarks>
/// The window itself is not restated here — it already lives in
/// <see cref="CueNumberDomain"/>, which the coercing boundaries share. This type
/// adds only what the <i>editing</i> path needs on top: the three-decimal
/// round-trip, duplicate detection, and the time-neighbour ordering rule.
/// </remarks>
public static class CueNumberValidator
{
    /// <summary>
    /// Validates <paramref name="candidate"/> as the new cue number for
    /// <paramref name="cueId"/>. <c>null</c> clears the number and is always
    /// allowed; committing a cue's existing number to itself is
    /// <see cref="CueNumberValidationKind.Ok"/>.
    /// </summary>
    public static CueNumberValidationResult Validate(
        double? candidate,
        Guid cueId,
        IReadOnlyList<Cue> cues)
    {
        if (candidate is not { } number)
        {
            return CueNumberValidationResult.Ok;
        }

        if (!IsWellFormatted(number))
        {
            return CueNumberValidationResult.InvalidFormat;
        }

        var target = cues.FirstOrDefault(cue => cue.Id == cueId);

        // Before the ordering rule, matching Swift: a number already in use is
        // reported as a duplicate even when it would also be out of order, so the
        // two cores show the same message for the same input.
        if (cues.Any(cue => cue.Id != cueId && cue.CueNumber == number))
        {
            return CueNumberValidationResult.Duplicate;
        }

        if (target is null)
        {
            return CueNumberValidationResult.Ok;
        }

        var neighbours = cues
            .Where(cue => cue.Id != cueId && cue.CueNumber is not null)
            .Select(cue => (cue.Time, Number: cue.CueNumber!.Value))
            .ToList();

        var previous = LatestNumber(neighbours.Where(n => n.Time < target.Time));
        var next = EarliestNumber(neighbours.Where(n => n.Time > target.Time));

        // Spelled as `!(a < b)` rather than `a >= b` to mirror Swift exactly. The
        // two differ on NaN, and while `number` is finite by this point a stored
        // neighbour number need not be — in-process construction is not clamped.
        if (previous is { } lower && !(lower < number))
        {
            return CueNumberValidationResult.OutOfRange(previous, next);
        }

        if (next is { } upper && !(number < upper))
        {
            return CueNumberValidationResult.OutOfRange(previous, next);
        }

        return CueNumberValidationResult.Ok;
    }

    /// <summary>
    /// Inside the window <i>and</i> expressible in three decimal places, which is
    /// what grandMA2 stores. Stricter than <see cref="CueNumberDomain.IsInDomain"/>
    /// on purpose — see that type for why the coercing boundaries stop short of
    /// this check.
    /// </summary>
    private static bool IsWellFormatted(double value)
    {
        if (!CueNumberDomain.IsInDomain(value))
        {
            return false;
        }

        // Three-decimal check via an integer round-trip on value * 1000. As in
        // FadeTimeFormatting, the rounding mode is immaterial to an integrality
        // test: every mode agrees on an already-integral value, and on a non-
        // integral one every mode moves it.
        var scaled = value * 1000;
        return Math.Round(scaled) == scaled;
    }

    /// <summary>
    /// The number of the latest-timed neighbour, or <c>null</c> when there is
    /// none. <c>MaxBy</c> is guarded rather than called blind: on an empty source
    /// it returns <c>default</c> only for nullable element types, and these
    /// elements are value tuples, so it would throw (measured).
    /// </summary>
    private static double? LatestNumber(IEnumerable<(double Time, double Number)> neighbours)
    {
        var candidates = neighbours.ToList();
        return candidates.Count == 0 ? null : candidates.MaxBy(n => n.Time).Number;
    }

    private static double? EarliestNumber(IEnumerable<(double Time, double Number)> neighbours)
    {
        var candidates = neighbours.ToList();
        return candidates.Count == 0 ? null : candidates.MinBy(n => n.Time).Number;
    }
}
