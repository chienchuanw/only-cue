using OnlyCue.Core.Document;

namespace OnlyCue.Core.Presentation;

/// <summary>
/// Resolves the Show-mode GO-by-type filter (#657) from the raw per-window scene
/// storage string; <c>null</c> means <i>All cues</i>. Mirrors Swift
/// <c>CueListGoFilter</c> (<c>OnlyCue/UI/CueListGoFilter.swift</c>).
/// </summary>
public static class CueListGoFilter
{
    /// <param name="rawId">The stored scene-storage string. <c>""</c> is its
    /// default and reads as All cues.</param>
    /// <param name="types">The document's live cue types. An id naming a type that
    /// has since been deleted also reads as All, rather than filtering the list
    /// down to nothing.</param>
    /// <param name="isShowMode">Named for the meaning rather than either caller's
    /// spelling, so a future mode that renders a read-only cue list has to decide
    /// deliberately instead of inheriting the filter by accident.</param>
    /// <remarks>
    /// <see cref="Guid.TryParseExact(string, string, out Guid)"/> with format
    /// <c>"D"</c>, not <see cref="Guid.TryParse(string, out Guid)"/>. Swift's
    /// <c>UUID(uuidString:)</c> accepts only the 8-4-4-4-12 hyphenated form in
    /// either case; plain <c>TryParse</c> also accepts braced, parenthesised and
    /// dash-less spellings (measured). A port using it would resolve a filter from
    /// a string macOS reads as All cues, and the two platforms would then walk
    /// different cues from the same stored value.
    /// </remarks>
    public static Guid? Resolve(string rawId, IReadOnlyList<CuePointType> types, bool isShowMode)
    {
        if (!isShowMode || !Guid.TryParseExact(rawId, "D", out var id))
        {
            return null;
        }

        return types.Any(type => type.Id == id) ? id : null;
    }
}

/// <summary>
/// Row-content opacity under the GO-by-type filter (#657): rows of another type
/// dim rather than disappear, so the walked type stands out while the
/// surrounding cues stay readable. Mirrors Swift <c>CueListRowOpacity</c>.
/// </summary>
/// <remarks>
/// <paramref name="dimmed"/> is injected rather than read from a layout constant,
/// so the rule stays pure: the golden vector seats the value it wants and the
/// design token remains each platform's own concern.
/// </remarks>
public static class CueListRowOpacity
{
    public static double Value(Guid cueTypeId, Guid? filter, double dimmed) =>
        filter is { } id && cueTypeId != id ? dimmed : 1;
}

/// <summary>
/// The cue list's empty-state instruction. Two different dead ends need two
/// different instructions: with no media loaded there is nothing to place a cue
/// against, so "press M" would be a lie. Mirrors Swift <c>CueListEmptyState</c>.
/// </summary>
public static class CueListEmptyState
{
    public static string Message(bool hasActiveItem) =>
        hasActiveItem
            ? "Press M to add a cue at the playhead."
            : "Import a media file to start adding cues.";
}
