using OnlyCue.Core.Document;
using OnlyCue.Core.Planning;

namespace OnlyCue.Core.Presentation;

/// <summary>
/// Maps a <see cref="CueNumberValidationResult"/> to the inline error shown under
/// the number field. Mirrors Swift <c>CueNumberErrorMessage</c>
/// (<c>OnlyCue/UI/CueNumberErrorMessage.swift</c>), pinned byte-for-byte by
/// <c>golden/cue-presentation-v1.json</c> (#837).
/// </summary>
public static class CueNumberErrorMessage
{
    /// <summary>
    /// The bounds are interpolated through
    /// <see cref="FadeTimeFormatting.FormatNumber"/> rather than written out, so
    /// the message cannot drift from the window it describes.
    /// </summary>
    /// <remarks>
    /// The separator is U+2013 EN DASH, written as an escape. Spelled literally it
    /// would be the one character in this contract that a hand-port can get wrong
    /// invisibly: a hyphen renders almost identically and looks like no change at
    /// all in a diff.
    /// </remarks>
    public static readonly string InvalidFormat =
        $"Use {FadeTimeFormatting.FormatNumber(CueNumberDomain.Minimum)}\u2013"
        + $"{FadeTimeFormatting.FormatNumber(CueNumberDomain.Maximum)}, up to 3 decimals.";

    public const string Duplicate = "Already in use.";

    /// <summary>The message for a non-OK result, or <c>null</c> for
    /// <see cref="CueNumberValidationKind.Ok"/>.</summary>
    public static string? Text(CueNumberValidationResult result) => result.Kind switch
    {
        CueNumberValidationKind.Ok => null,
        CueNumberValidationKind.InvalidFormat => InvalidFormat,
        CueNumberValidationKind.Duplicate => Duplicate,
        CueNumberValidationKind.OutOfRange => OutOfRangeText(result.LowerExclusive, result.UpperExclusive),
        _ => throw new ArgumentOutOfRangeException(nameof(result), result.Kind, "unknown validation kind")
    };

    private static string OutOfRangeText(double? lowerExclusive, double? upperExclusive) =>
        (lowerExclusive, upperExclusive) switch
        {
            ({ } lower, { } upper) =>
                $"Must be between {FadeTimeFormatting.FormatNumber(lower)} and "
                + $"{FadeTimeFormatting.FormatNumber(upper)}.",
            ({ } lower, null) => $"Must be greater than {FadeTimeFormatting.FormatNumber(lower)}.",
            (null, { } upper) => $"Must be less than {FadeTimeFormatting.FormatNumber(upper)}.",
            // The validator never produces OutOfRange with both bounds absent, but
            // a UI helper falls back rather than asserting.
            (null, null) => InvalidFormat
        };
}
