using System.Globalization;
using System.Text;

namespace OnlyCue.Core.Ma2;

/// <summary>
/// Sanitises a clip name into a grandMA2-safe sequence name (#686). Mirrors
/// Swift <c>MA2Name</c> (<c>OnlyCue/MA2/MA2Name.swift</c>).
/// </summary>
public static class Ma2Name
{
    private static readonly char[] Separators = [' ', '\t'];

    /// <summary>
    /// ASCII printable only, embedded double quotes stripped, whitespace runs
    /// collapsed; falls back to <c>OnlyCue &lt;slot&gt;</c> when nothing usable
    /// survives (e.g. an all-CJK name).
    /// </summary>
    /// <remarks>
    /// Swift filters <b>unicode scalars</b>, so a non-BMP character such as 🎵 is
    /// dropped whole. Iterating <c>char</c> here would instead walk UTF-16 code
    /// units and split that surrogate pair into two halves — which, because this
    /// filter admits nothing but ASCII, are rejected exactly as the whole scalar
    /// was. Fuzzing the two forms over 400k strings (lone surrogates included)
    /// found <b>zero</b> divergences, so the choice is not observable today and
    /// the golden vectors cannot pin it.
    ///
    /// It stays scalar-level regardless, because that equivalence is a property of
    /// the current filter and not of the code: widen the kept range past ASCII and
    /// <c>char</c> iteration would begin emitting broken halves of astral
    /// characters while Swift went on dropping them whole.
    /// </remarks>
    public static string Sanitize(string raw, int fallbackSlot)
    {
        var asciiPrintable = new StringBuilder(raw.Length);
        foreach (var rune in raw.EnumerateRunes())
        {
            if (rune.IsAscii && rune.Value >= 0x20 && rune.Value != 0x22)  // 0x22 = "
            {
                asciiPrintable.Append((char)rune.Value);
            }
        }

        var collapsed = string.Join(
            ' ',
            asciiPrintable.ToString().Split(Separators, StringSplitOptions.RemoveEmptyEntries));

        return collapsed.Length == 0
            ? $"OnlyCue {fallbackSlot.ToString(CultureInfo.InvariantCulture)}"
            : collapsed;
    }
}
