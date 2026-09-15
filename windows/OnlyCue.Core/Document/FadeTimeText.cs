using System.Globalization;
using System.Text.Json.Serialization;

namespace OnlyCue.Core.Document;

/// <summary>
/// The text half of <see cref="FadeTime"/>: the typed-input grammar and the two
/// display spellings. Mirrors the <c>parse</c> / <c>format</c> / <c>cellDisplay</c>
/// members of Swift <c>FadeTime</c> (<c>OnlyCue/Document/FadeTime.swift</c>),
/// pinned by <c>golden/cue-presentation-v1.json</c> (#837).
/// </summary>
public sealed partial class FadeTime
{
    /// <summary>
    /// Parses a fade-time string: <c>"1"</c> / <c>"1.5"</c> (symmetric) or
    /// <c>"1/2"</c> (split). <c>null</c> means the string is rejected — there is
    /// no half-parsed result.
    /// </summary>
    /// <remarks>
    /// <para>
    /// This is a trust boundary — the string comes from a text field — and the
    /// two cores must reject exactly the same set, or a fade typed on one
    /// platform would be refused on the other. Three divergences between Swift's
    /// <c>Double(String)</c> and .NET's <c>double.TryParse</c> are handled here,
    /// each measured on Swift 6.3.3 / .NET 10.0.11 rather than assumed:
    /// </para>
    /// <list type="number">
    /// <item><b>Whitespace set.</b> See <see cref="TrimSwiftWhitespace"/>.</item>
    /// <item><b>Leading plus.</b> <c>"+1"</c> parses to 1 under
    /// <see cref="ParseStyles"/>, and Swift rejects it — but only because of an
    /// explicit prefix guard, which is therefore reproduced below rather than
    /// left to the parser.</item>
    /// <item><b>Non-finite words.</b> .NET accepts <c>"infinity"</c> and
    /// <c>"nan"</c> whatever the styles, and Swift does not — so those spellings
    /// have to be rejected here explicitly. What rejects them is the
    /// <c>0…Maximum</c> range, not the <c>IsFinite</c> call: no non-finite value
    /// satisfies those bounds, so removing <c>IsFinite</c> changes no answer
    /// (verified by mutation — the mutant survives the whole vector, exactly as
    /// on the Swift original and in <see cref="CueNumberDomain"/>). It is stated
    /// rather than relied upon, because reordering the bounds or folding them
    /// into a clamp helper would silently change the non-finite answer, and
    /// because the two cores should read alike.</item>
    /// </list>
    /// <para>
    /// There is deliberately <i>no</i> counterpart to Swift's <c>isHexFloat</c>
    /// guard. Swift needed one because <c>Double(String)</c> implements the whole
    /// C99 <c>strtod</c> grammar and read <c>"0x1p3"</c> as an 8 second fade
    /// (#841); .NET has no hex-float grammar at all, so every <c>0x…</c> spelling
    /// is already rejected by <see cref="ParseStyles"/> (measured, including
    /// <c>"0x10"</c> and <c>"-0x0p0"</c>). Adding the guard anyway would be dead
    /// code no mutation could kill, which reads as protection that isn't there.
    /// The shared outcome is pinned by the vector's hex cases instead.
    /// </para>
    /// </remarks>
    public static FadeTime? Parse(string text)
    {
        var trimmed = TrimSwiftWhitespace(text);
        if (trimmed.Length == 0)
        {
            return null;
        }

        // Swift splits with `omittingEmptySubsequences: false`, which is what
        // `string.Split` does by default — so `"1/"` stays two parts and is
        // rejected by the empty leg rather than collapsing to a valid `"1"`.
        var parts = trimmed.Split('/');
        return parts.Length switch
        {
            1 => ParseNonNegative(parts[0]) is { } value ? Symmetric(value) : null,
            2 => ParseNonNegative(parts[0]) is { } fadeIn && ParseNonNegative(parts[1]) is { } fadeOut
                ? new FadeTime { FadeIn = fadeIn, FadeOut = fadeOut }
                : null,
            _ => null
        };
    }

    /// <summary>
    /// Canonical user-facing form: <c>"1.5"</c> symmetric, <c>"1/2"</c> split.
    /// Whole numbers drop the trailing <c>.0</c> (see
    /// <see cref="FadeTimeFormatting.FormatNumber"/>).
    /// </summary>
    public string Format() =>
        FadeIn == FadeOut
            ? FadeTimeFormatting.FormatNumber(FadeIn)
            : $"{FadeTimeFormatting.FormatNumber(FadeIn)}/{FadeTimeFormatting.FormatNumber(FadeOut)}";

    /// <summary>
    /// Cue-list fade cell text. Seconds is the column's implicit unit, so the cell
    /// shows the bare <see cref="Format"/> number and blanks a zero fade, so an
    /// unset fade reads as absence rather than <c>"0"</c> (#804).
    /// </summary>
    /// <remarks>
    /// <para>
    /// Compares the two legs rather than <c>this == Zero</c>: Swift's
    /// <c>FadeTime</c> is an <c>Equatable</c> struct, but this one is a class with
    /// no value equality, so <c>== Zero</c> would be a reference comparison and
    /// would never be true — every zero fade would render as <c>"0"</c>.
    /// </para>
    /// <para>
    /// <see cref="JsonIgnoreAttribute"/> because <see cref="FadeTime"/> is a
    /// persisted model type and <c>System.Text.Json</c> serialises public
    /// getter-only properties: without it this display string is written into
    /// every <c>.cuelist</c> as a <c>cellDisplay</c> key macOS neither writes nor
    /// expects. Swift is immune — its synthesized <c>Codable</c> only encodes
    /// stored properties, and <c>cellDisplay</c> is computed. The migration golden
    /// vector caught this; <c>MediaItem.ResolvedName</c> carries the attribute for
    /// the same reason.
    /// </para>
    /// </remarks>
    [JsonIgnore]
    public string CellDisplay => FadeIn == 0 && FadeOut == 0 ? string.Empty : Format();

    /// <summary>
    /// Swift's <c>Double(String)</c> tolerates no surrounding whitespace, so
    /// <see cref="NumberStyles.Float"/> is <i>not</i> used: its
    /// <c>AllowLeadingWhite</c> / <c>AllowTrailingWhite</c> would accept
    /// <c>"1 / 2"</c>, which macOS rejects.
    /// </summary>
    private const NumberStyles ParseStyles =
        NumberStyles.AllowLeadingSign | NumberStyles.AllowDecimalPoint | NumberStyles.AllowExponent;

    private static double? ParseNonNegative(string text)
    {
        if (text.Length == 0 || text[0] == '+')
        {
            return null;
        }

        if (!double.TryParse(text, ParseStyles, CultureInfo.InvariantCulture, out var value))
        {
            return null;
        }

        return double.IsFinite(value) && value >= 0 && value <= Maximum ? value : null;
    }

    /// <summary>
    /// Trims the character set Swift's <c>.whitespaces</c> covers — Unicode
    /// <c>Zs</c> (space separator) plus U+0009 — and nothing else.
    /// </summary>
    /// <remarks>
    /// <c>string.Trim()</c> is the trap: it also strips <c>\n</c> and <c>\r</c>,
    /// which <c>.whitespaces</c> excludes, so <c>"1.5\n"</c> would be accepted
    /// here and rejected on macOS. Tab has to be named explicitly because its
    /// Unicode category is <c>Control</c>, not <c>SpaceSeparator</c> (measured).
    /// Iterating <c>char</c>s is safe because no <c>Zs</c> character lives outside
    /// the BMP, so none is a surrogate pair.
    /// </remarks>
    private static string TrimSwiftWhitespace(string text)
    {
        var start = 0;
        var end = text.Length;
        while (start < end && IsSwiftWhitespace(text[start]))
        {
            start++;
        }

        while (end > start && IsSwiftWhitespace(text[end - 1]))
        {
            end--;
        }

        return text[start..end];
    }

    private static bool IsSwiftWhitespace(char value) =>
        value == '\t' || CharUnicodeInfo.GetUnicodeCategory(value) == UnicodeCategory.SpaceSeparator;
}
