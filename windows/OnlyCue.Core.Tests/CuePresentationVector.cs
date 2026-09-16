using System.Text.Json.Serialization;

namespace OnlyCue.Core.Tests;

/// <summary>
/// DTOs mirroring <c>CuePresentationGoldenVector</c> in
/// <c>OnlyCueTests/CuePresentationGoldenVectorCases.swift</c>. macOS is the source
/// of truth for <c>golden/cue-presentation-v1.json</c>; this side only ever reads
/// it (epic #728, M1d — vector 8).
/// </summary>
/// <remarks>
/// Every optional below is a <i>real</i> state, not a gap in the fixture: Swift's
/// synthesized <c>Codable</c> uses <c>encodeIfPresent</c>, so a <c>nil</c> is an
/// absent JSON key rather than a <c>null</c>. Absent <c>expect…</c> means
/// "rejected" / "no cue" / "All cues" / "no message", and absent
/// <c>cueNumber</c> / <c>candidate</c> / <c>filter</c> / <c>typeID</c> means
/// unnumbered / clearing / unfiltered.
/// </remarks>
public sealed record CuePresentationVector(
    [property: JsonPropertyName("contract")] string Contract,
    [property: JsonPropertyName("version")] int Version,
    [property: JsonPropertyName("note")] string Note,
    [property: JsonPropertyName("fadeParse")] IReadOnlyList<FadeParseCase> FadeParse,
    [property: JsonPropertyName("fadeFormat")] IReadOnlyList<FadeFormatCase> FadeFormat,
    [property: JsonPropertyName("cueNumberValidation")] IReadOnlyList<CueNumberValidationCase> CueNumberValidation,
    [property: JsonPropertyName("cueNumberErrors")] IReadOnlyList<CueNumberErrorCase> CueNumberErrors,
    [property: JsonPropertyName("sectionCount")] IReadOnlyList<SectionCountCase> SectionCount,
    [property: JsonPropertyName("rowTapIntent")] IReadOnlyList<RowTapIntentCase> RowTapIntent,
    [property: JsonPropertyName("rangeSelection")] IReadOnlyList<RangeSelectionCase> RangeSelection,
    [property: JsonPropertyName("rowFill")] IReadOnlyList<RowFillCase> RowFill,
    [property: JsonPropertyName("goFilter")] IReadOnlyList<GoFilterCase> GoFilter,
    [property: JsonPropertyName("rowOpacity")] IReadOnlyList<RowOpacityCase> RowOpacity,
    [property: JsonPropertyName("activeCue")] IReadOnlyList<ActiveCueCase> ActiveCue,
    [property: JsonPropertyName("emptyState")] IReadOnlyList<EmptyStateCase> EmptyState)
{
    private const string RelativePath = "golden/cue-presentation-v1.json";

    public static CuePresentationVector Load() => GoldenFiles.Load<CuePresentationVector>(RelativePath);
}

/// <summary>A cue reduced to the four fields the presentation layer reads.</summary>
public sealed record PresentationCueFixture(
    [property: JsonPropertyName("id")] string Id,
    [property: JsonPropertyName("typeID")] string TypeId,
    [property: JsonPropertyName("time")] string Time,
    [property: JsonPropertyName("cueNumber")] string? CueNumber);

public sealed record FadeParseCase(
    [property: JsonPropertyName("name")] string Name,
    [property: JsonPropertyName("input")] string Input,
    [property: JsonPropertyName("expectFadeIn")] string? ExpectFadeIn,
    [property: JsonPropertyName("expectFadeOut")] string? ExpectFadeOut)
{
    /// <summary><c>parse</c> returns an optional whole, never a half-parsed pair,
    /// so one absent leg means the whole string was rejected.</summary>
    public bool IsRejected => ExpectFadeIn is null && ExpectFadeOut is null;
}

public sealed record FadeFormatCase(
    [property: JsonPropertyName("name")] string Name,
    [property: JsonPropertyName("fadeIn")] string FadeIn,
    [property: JsonPropertyName("fadeOut")] string FadeOut,
    [property: JsonPropertyName("expectFormat")] string ExpectFormat,
    [property: JsonPropertyName("expectCellDisplay")] string ExpectCellDisplay);

/// <summary>The flattened <c>CueNumberValidator.Result</c>: a case name plus the
/// two bounds that only <c>outOfRange</c> carries.</summary>
public sealed record VectorValidationResult(
    [property: JsonPropertyName("kind")] string Kind,
    [property: JsonPropertyName("lowerExclusive")] string? LowerExclusive,
    [property: JsonPropertyName("upperExclusive")] string? UpperExclusive);

public sealed record CueNumberValidationCase(
    [property: JsonPropertyName("name")] string Name,
    [property: JsonPropertyName("cues")] IReadOnlyList<PresentationCueFixture> Cues,
    [property: JsonPropertyName("targetID")] string TargetId,
    [property: JsonPropertyName("candidate")] string? Candidate,
    [property: JsonPropertyName("expect")] VectorValidationResult Expect);

public sealed record CueNumberErrorCase(
    [property: JsonPropertyName("name")] string Name,
    [property: JsonPropertyName("result")] VectorValidationResult Result,
    [property: JsonPropertyName("expect")] string? Expect);

public sealed record SectionCountCase(
    [property: JsonPropertyName("name")] string Name,
    [property: JsonPropertyName("count")] int Count,
    [property: JsonPropertyName("expect")] string Expect);

public sealed record RowTapIntentCase(
    [property: JsonPropertyName("name")] string Name,
    [property: JsonPropertyName("target")] string Target,
    [property: JsonPropertyName("modifier")] string Modifier,
    [property: JsonPropertyName("isReadOnly")] bool IsReadOnly,
    [property: JsonPropertyName("expect")] string Expect);

/// <summary>A Shift-click range (#790). <c>Expect</c> is emitted in displayed
/// order for a readable diff, but the function returns a <i>set</i> — compare it
/// as one, and as parsed <c>Guid</c>s rather than strings.</summary>
public sealed record RangeSelectionCase(
    [property: JsonPropertyName("name")] string Name,
    [property: JsonPropertyName("displayed")] IReadOnlyList<string> Displayed,
    [property: JsonPropertyName("anchor")] string? Anchor,
    [property: JsonPropertyName("target")] string Target,
    [property: JsonPropertyName("expect")] IReadOnlyList<string> Expect);

public sealed record RowFillCase(
    [property: JsonPropertyName("name")] string Name,
    [property: JsonPropertyName("isSelected")] bool IsSelected,
    [property: JsonPropertyName("isCurrent")] bool IsCurrent,
    [property: JsonPropertyName("hasTint")] bool HasTint,
    [property: JsonPropertyName("expect")] string Expect);

public sealed record GoFilterCase(
    [property: JsonPropertyName("name")] string Name,
    [property: JsonPropertyName("rawID")] string RawId,
    [property: JsonPropertyName("typeIDs")] IReadOnlyList<string> TypeIds,
    [property: JsonPropertyName("isShowMode")] bool IsShowMode,
    [property: JsonPropertyName("expect")] string? Expect);

public sealed record RowOpacityCase(
    [property: JsonPropertyName("name")] string Name,
    [property: JsonPropertyName("cueTypeID")] string CueTypeId,
    [property: JsonPropertyName("filter")] string? Filter,
    [property: JsonPropertyName("dimmed")] string Dimmed,
    [property: JsonPropertyName("expect")] string Expect);

public sealed record ActiveCueCase(
    [property: JsonPropertyName("name")] string Name,
    [property: JsonPropertyName("cues")] IReadOnlyList<PresentationCueFixture> Cues,
    [property: JsonPropertyName("currentTime")] string CurrentTime,
    [property: JsonPropertyName("typeID")] string? TypeId,
    [property: JsonPropertyName("expectCueID")] string? ExpectCueId);

public sealed record EmptyStateCase(
    [property: JsonPropertyName("name")] string Name,
    [property: JsonPropertyName("hasActiveItem")] bool HasActiveItem,
    [property: JsonPropertyName("expect")] string Expect);
