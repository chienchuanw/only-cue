using System.Globalization;

namespace OnlyCue.Core.Presentation;

/// <summary>
/// The cue-list section header's count label. Mirrors the pure
/// <c>countText(for:)</c> helper on Swift <c>CueListSectionHeader</c>
/// (<c>OnlyCue/UI/CueListSectionHeader.swift</c>) — only the text, not the view.
/// </summary>
public static class CueListSectionHeader
{
    /// <remarks>
    /// English-only pluralisation, matching macOS: the app ships one language, and
    /// a localisation would have to change both cores together anyway. The count
    /// is formatted with the invariant culture so a machine set to a
    /// digit-grouping locale cannot turn <c>1000</c> into <c>1,000</c> here while
    /// macOS spells it plainly.
    /// </remarks>
    public static string CountText(int count) =>
        count == 1 ? "1 cue" : $"{count.ToString(CultureInfo.InvariantCulture)} cues";
}
