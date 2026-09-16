using OnlyCue.Core.Document;
using OnlyCue.Core.Presentation;
using Xunit;

namespace OnlyCue.Core.Tests;

/// <summary>
/// The Windows half of the cue-list presentation contract (epic #728, M1d —
/// vector 8). macOS emits <c>golden/cue-presentation-v1.json</c> from the Swift
/// implementation; this suite asserts the C# re-implementation reproduces every
/// case, so drift between the two hand-maintained cores fails CI instead of
/// shipping two cue lists that disagree about what the designer typed.
/// </summary>
public class CuePresentationGoldenVectorTests
{
    private static readonly CuePresentationVector Vector = CuePresentationVector.Load();

    public static TheoryData<string> FadeParseNames => Names(Vector.FadeParse.Select(c => c.Name));

    public static TheoryData<string> FadeFormatNames => Names(Vector.FadeFormat.Select(c => c.Name));

    public static TheoryData<string> ValidationNames => Names(Vector.CueNumberValidation.Select(c => c.Name));

    public static TheoryData<string> ErrorNames => Names(Vector.CueNumberErrors.Select(c => c.Name));

    public static TheoryData<string> SectionCountNames => Names(Vector.SectionCount.Select(c => c.Name));

    public static TheoryData<string> RowTapNames => Names(Vector.RowTapIntent.Select(c => c.Name));

    public static TheoryData<string> RangeSelectionNames => Names(Vector.RangeSelection.Select(c => c.Name));

    public static TheoryData<string> RowFillNames => Names(Vector.RowFill.Select(c => c.Name));

    public static TheoryData<string> GoFilterNames => Names(Vector.GoFilter.Select(c => c.Name));

    public static TheoryData<string> RowOpacityNames => Names(Vector.RowOpacity.Select(c => c.Name));

    public static TheoryData<string> ActiveCueNames => Names(Vector.ActiveCue.Select(c => c.Name));

    public static TheoryData<string> EmptyStateNames => Names(Vector.EmptyState.Select(c => c.Name));

    [Fact]
    public void GoldenFile_IsTheExpectedContract()
    {
        Assert.Equal("cue-presentation", Vector.Contract);
        Assert.Equal(1, Vector.Version);
        // Group counts, not just NotEmpty: a vector that lost most of a group to a
        // regenerate would still be "not empty" while quietly dropping coverage.
        Assert.Equal(8, Vector.RowFill.Count);
        // 12 since #790 split Ctrl/Cmd from Shift — 8 here would mean the vector
        // was regenerated from a core that still collapses them.
        Assert.Equal(12, Vector.RowTapIntent.Count);
        Assert.NotEmpty(Vector.RangeSelection);
        Assert.NotEmpty(Vector.FadeParse);
        Assert.NotEmpty(Vector.CueNumberValidation);
    }

    [Theory]
    [MemberData(nameof(FadeParseNames))]
    public void FadeParse_ReproducesGoldenCase(string name)
    {
        var golden = Vector.FadeParse.Single(c => c.Name == name);

        var actual = FadeTime.Parse(golden.Input);

        // Built inside the failure branch, not passed to `Assert.True`: the message
        // argument is evaluated eagerly, so describing `actual` there would
        // dereference null on exactly the runs that pass.
        if (golden.IsRejected)
        {
            if (actual is not null)
            {
                Assert.Fail(
                    $"fadeParse '{name}': expected {Describe(golden.Input)} to be rejected, "
                    + $"got {actual.Format()}");
            }

            return;
        }

        if (actual is null)
        {
            Assert.Fail($"fadeParse '{name}': expected {Describe(golden.Input)} to parse, got null");
        }

        AssertDouble(GoldenDouble.Parse(golden.ExpectFadeIn!), actual!.FadeIn, $"fadeParse '{name}' fadeIn");
        AssertDouble(GoldenDouble.Parse(golden.ExpectFadeOut!), actual.FadeOut, $"fadeParse '{name}' fadeOut");
    }

    [Theory]
    [MemberData(nameof(FadeFormatNames))]
    public void FadeFormat_ReproducesGoldenCase(string name)
    {
        var golden = Vector.FadeFormat.Single(c => c.Name == name);
        var fade = new FadeTime
        {
            FadeIn = GoldenDouble.Parse(golden.FadeIn),
            FadeOut = GoldenDouble.Parse(golden.FadeOut)
        };

        Assert.Equal(golden.ExpectFormat, fade.Format());
        // Pinned separately from Format because one is not derivable from the
        // other: a zero fade formats as "0" but its cell is blank (#804).
        Assert.Equal(golden.ExpectCellDisplay, fade.CellDisplay);
    }

    [Theory]
    [MemberData(nameof(ValidationNames))]
    public void CueNumberValidation_ReproducesGoldenCase(string name)
    {
        var golden = Vector.CueNumberValidation.Single(c => c.Name == name);

        var actual = CueNumberValidator.Validate(
            GoldenDouble.ParseOrNull(golden.Candidate),
            Guid.Parse(golden.TargetId),
            Cues(golden.Cues));

        AssertValidationResult(golden.Expect, actual, $"cueNumberValidation '{name}'");
    }

    [Theory]
    [MemberData(nameof(ErrorNames))]
    public void CueNumberErrorMessage_ReproducesGoldenCase(string name)
    {
        var golden = Vector.CueNumberErrors.Single(c => c.Name == name);

        var actual = CueNumberErrorMessage.Text(ValidationResult(golden.Result));

        // Ordinal, so the en dash in the format message is compared as the code
        // point it is rather than collated against a hyphen by some culture.
        Assert.Equal(golden.Expect, actual, StringComparer.Ordinal);
    }

    [Theory]
    [MemberData(nameof(SectionCountNames))]
    public void SectionCount_ReproducesGoldenCase(string name)
    {
        var golden = Vector.SectionCount.Single(c => c.Name == name);

        Assert.Equal(golden.Expect, CueListSectionHeader.CountText(golden.Count));
    }

    [Theory]
    [MemberData(nameof(RowTapNames))]
    public void RowTapIntent_ReproducesGoldenCase(string name)
    {
        var golden = Vector.RowTapIntent.Single(c => c.Name == name);

        var actual = CueRowTap.Intent(TapTarget(golden.Target), TapModifier(golden.Modifier), golden.IsReadOnly);

        Assert.Equal(TapIntent(golden.Expect), actual);
    }

    [Theory]
    [MemberData(nameof(RangeSelectionNames))]
    public void RangeSelection_ReproducesGoldenCase(string name)
    {
        var golden = Vector.RangeSelection.Single(c => c.Name == name);

        var actual = CueRangeSelection.Range(
            golden.Displayed.Select(Guid.Parse).ToList(),
            golden.Anchor is null ? null : Guid.Parse(golden.Anchor),
            Guid.Parse(golden.Target));

        // A set, compared as a set of parsed Guids: the vector emits the ids in
        // displayed order only so the committed JSON diffs readably, and Swift's
        // `uuidString` uppercases the hex where .NET's `Guid.ToString()` lowercases
        // it, so a string compare would fail an implementation that is correct.
        Assert.Equal(golden.Expect.Select(Guid.Parse).ToHashSet(), actual.ToHashSet());
    }

    [Theory]
    [MemberData(nameof(RowFillNames))]
    public void RowFill_ReproducesGoldenCase(string name)
    {
        var golden = Vector.RowFill.Single(c => c.Name == name);

        var actual = CueRowFill.Resolution(golden.IsSelected, golden.IsCurrent, golden.HasTint);

        Assert.Equal(FillResolution(golden.Expect), actual);
    }

    [Theory]
    [MemberData(nameof(GoFilterNames))]
    public void GoFilter_ReproducesGoldenCase(string name)
    {
        var golden = Vector.GoFilter.Single(c => c.Name == name);
        var types = golden.TypeIds
            .Select(id => new CuePointType { Id = Guid.Parse(id) })
            .ToList();

        var actual = CueListGoFilter.Resolve(golden.RawId, types, golden.IsShowMode);

        // Compared as parsed Guids, never as strings: Swift's `uuidString`
        // uppercases the hex where .NET's `Guid.ToString()` lowercases it, so a
        // string compare would fail on an implementation that is in fact correct.
        Assert.Equal(golden.Expect is null ? null : Guid.Parse(golden.Expect), actual);
    }

    [Theory]
    [MemberData(nameof(RowOpacityNames))]
    public void RowOpacity_ReproducesGoldenCase(string name)
    {
        var golden = Vector.RowOpacity.Single(c => c.Name == name);

        var actual = CueListRowOpacity.Value(
            Guid.Parse(golden.CueTypeId),
            golden.Filter is null ? null : Guid.Parse(golden.Filter),
            GoldenDouble.Parse(golden.Dimmed));

        AssertDouble(GoldenDouble.Parse(golden.Expect), actual, $"rowOpacity '{name}'");
    }

    [Theory]
    [MemberData(nameof(ActiveCueNames))]
    public void ActiveCue_ReproducesGoldenCase(string name)
    {
        var golden = Vector.ActiveCue.Single(c => c.Name == name);
        var item = new MediaItem { Cues = Cues(golden.Cues) };

        var actual = item.ActiveCue(
            GoldenDouble.Parse(golden.CurrentTime),
            golden.TypeId is null ? null : Guid.Parse(golden.TypeId));

        Assert.Equal(golden.ExpectCueId is null ? null : Guid.Parse(golden.ExpectCueId), actual?.Id);
    }

    [Theory]
    [MemberData(nameof(EmptyStateNames))]
    public void EmptyState_ReproducesGoldenCase(string name)
    {
        var golden = Vector.EmptyState.Single(c => c.Name == name);

        Assert.Equal(golden.Expect, CueListEmptyState.Message(golden.HasActiveItem));
    }

    /// <summary>
    /// Builds the case's cues through plain construction, deliberately <i>not</i>
    /// through <see cref="Cue.Clamped"/>. The Swift generator uses the memberwise
    /// initialiser, which leaves <c>cueNumber</c> alone — only <c>init(from:)</c>
    /// coerces an out-of-domain number (#830), and <see cref="Cue.Clamped"/> is
    /// this port's stand-in for that decode path. Running it here would silently
    /// normalise fixtures the vector means to be seen raw.
    /// </summary>
    private static List<Cue> Cues(IReadOnlyList<PresentationCueFixture> fixtures) =>
        fixtures.Select(fixture => new Cue
        {
            Id = Guid.Parse(fixture.Id),
            TypeId = Guid.Parse(fixture.TypeId),
            Time = GoldenDouble.Parse(fixture.Time),
            CueNumber = GoldenDouble.ParseOrNull(fixture.CueNumber)
        }).ToList();

    private static CueNumberValidationResult ValidationResult(VectorValidationResult golden) =>
        new(
            ValidationKind(golden.Kind),
            GoldenDouble.ParseOrNull(golden.LowerExclusive),
            GoldenDouble.ParseOrNull(golden.UpperExclusive));

    private static void AssertValidationResult(
        VectorValidationResult expected,
        CueNumberValidationResult actual,
        string label)
    {
        Assert.True(
            ValidationKind(expected.Kind) == actual.Kind,
            $"{label}: expected kind '{expected.Kind}', got {actual.Kind}");
        AssertDouble(GoldenDouble.ParseOrNull(expected.LowerExclusive), actual.LowerExclusive, $"{label} lower");
        AssertDouble(GoldenDouble.ParseOrNull(expected.UpperExclusive), actual.UpperExclusive, $"{label} upper");
    }

    // The four mappings below are written as explicit switches rather than
    // `Enum.Parse(..., ignoreCase: true)` on purpose. A name-based transform would
    // keep passing if either side renamed a case in step with the other — which is
    // exactly the drift the vector exists to catch — and would also let a new case
    // appear on one platform unnoticed. Spelled out, an unknown name is a failure.
    private static CueNumberValidationKind ValidationKind(string raw) => raw switch
    {
        "ok" => CueNumberValidationKind.Ok,
        "invalidFormat" => CueNumberValidationKind.InvalidFormat,
        "duplicate" => CueNumberValidationKind.Duplicate,
        "outOfRange" => CueNumberValidationKind.OutOfRange,
        _ => throw new InvalidDataException($"unknown validation kind '{raw}'")
    };

    private static CueRowFillResolution FillResolution(string raw) => raw switch
    {
        "current" => CueRowFillResolution.Current,
        "tint" => CueRowFillResolution.Tint,
        "selectionFallback" => CueRowFillResolution.SelectionFallback,
        "clear" => CueRowFillResolution.Clear,
        _ => throw new InvalidDataException($"unknown row fill '{raw}'")
    };

    private static CueRowTapTarget TapTarget(string raw) => raw switch
    {
        "field" => CueRowTapTarget.Field,
        "stripe" => CueRowTapTarget.Stripe,
        _ => throw new InvalidDataException($"unknown tap target '{raw}'")
    };

    private static CueRowTapModifier TapModifier(string raw) => raw switch
    {
        "plain" => CueRowTapModifier.Plain,
        "toggle" => CueRowTapModifier.Toggle,
        "range" => CueRowTapModifier.Range,
        _ => throw new InvalidDataException($"unknown tap modifier '{raw}'")
    };

    private static CueRowTapIntent TapIntent(string raw) => raw switch
    {
        "beginEdit" => CueRowTapIntent.BeginEdit,
        "toggleSelection" => CueRowTapIntent.ToggleSelection,
        "extendRange" => CueRowTapIntent.ExtendRange,
        "selectAndSeek" => CueRowTapIntent.SelectAndSeek,
        "ignored" => CueRowTapIntent.Ignored,
        _ => throw new InvalidDataException($"unknown tap intent '{raw}'")
    };

    private static void AssertDouble(double? expected, double? actual, string label) =>
        Assert.True(
            GoldenDouble.BitwiseEquals(expected, actual),
            $"{label}: expected {GoldenDouble.Describe(expected)}, got {GoldenDouble.Describe(actual)}");

    /// <summary>Renders control characters visibly, so a whitespace-set failure
    /// names the character that differed instead of printing it.</summary>
    private static string Describe(string input) =>
        "\"" + input.Replace("\t", "\\t").Replace("\n", "\\n").Replace("\r", "\\r") + "\"";

    private static TheoryData<string> Names(IEnumerable<string> names)
    {
        var data = new TheoryData<string>();
        foreach (var name in names)
        {
            data.Add(name);
        }

        return data;
    }
}
