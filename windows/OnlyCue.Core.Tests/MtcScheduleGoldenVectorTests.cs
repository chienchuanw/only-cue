using OnlyCue.Core.Midi;
using Xunit;

namespace OnlyCue.Core.Tests;

/// <summary>
/// The Windows half of the MTC scheduling contract (epic #728, M3 slice 2).
/// macOS emits <c>golden/mtc-schedule-v1.json</c> from the Swift
/// <c>MTCSchedule</c>; this suite asserts the C# re-implementation reproduces
/// every case exactly.
/// </summary>
/// <remarks>
/// <c>batchChain</c> is the load-bearing op: the windows are tiled, so
/// <c>concat(windows)</c> must equal <c>combined</c>. A message dropped at a seam
/// and one duplicated there fail differently, which is what makes the quantise in
/// <c>QuarterFrameIndexAtOrAfter</c> testable at all.
/// </remarks>
public class MtcScheduleGoldenVectorTests
{
    private static readonly MtcScheduleVector Vector = MtcScheduleVector.Load();

    public static TheoryData<string> CaseLabels
    {
        get
        {
            var data = new TheoryData<string>();
            foreach (var label in Vector.Cases.Select(c => c.Label))
            {
                data.Add(label);
            }

            return data;
        }
    }

    [Fact]
    public void GoldenFile_IsTheExpectedContract()
    {
        Assert.Equal("mtc-schedule", Vector.Contract);
        Assert.Equal(1, Vector.Version);
        Assert.NotEmpty(Vector.Cases);
    }

    [Theory]
    [MemberData(nameof(CaseLabels))]
    public void CSharpCore_ReproducesGoldenCase(string label)
    {
        var goldenCase = Vector.Cases.Single(c => c.Label == label);
        var schedule = ScheduleFrom(goldenCase);

        switch (goldenCase.Op)
        {
            case "cadence":
                AssertDouble(
                    goldenCase.Expect.TicksPerQuarterFrame,
                    schedule.TicksPerQuarterFrame,
                    label,
                    "ticksPerQuarterFrame");
                break;
            case "sequenceTimecode":
                Assert.Equal(
                    goldenCase.Expect.Timecode,
                    schedule.TimecodeForSequence(Required(goldenCase.Input.SequenceIndex, label, "sequenceIndex"))
                        .DisplayString);
                break;
            case "quarterFrame":
                AssertQuarterFrame(goldenCase, schedule);
                break;
            case "batch":
                Assert.Equal(
                    goldenCase.Expect.Messages,
                    Encode(schedule.Batch(
                        Required(goldenCase.Input.From, label, "from"),
                        Required(goldenCase.Input.Until, label, "until"))));
                break;
            case "batchChain":
                AssertChain(goldenCase, schedule);
                break;
            default:
                throw new InvalidDataException($"unknown golden op '{goldenCase.Op}'");
        }
    }

    private static void AssertQuarterFrame(MtcScheduleCase goldenCase, MtcSchedule schedule)
    {
        var index = Required(goldenCase.Input.QuarterFrameIndex, goldenCase.Label, "quarterFrameIndex");
        Assert.Equal(goldenCase.Expect.Byte, schedule.ByteForQuarterFrame(index));
        Assert.Equal(goldenCase.Expect.Timestamp, schedule.TimestampForQuarterFrame(index));
    }

    private static void AssertChain(MtcScheduleCase goldenCase, MtcSchedule schedule)
    {
        var label = goldenCase.Label;
        var boundaries = Required(goldenCase.Input.Boundaries, label, "boundaries");
        var windows = new List<IReadOnlyList<IReadOnlyList<ulong>>>(
            boundaries.Zip(boundaries.Skip(1), (from, until) => Encode(schedule.Batch(from, until))));
        var combined = Encode(schedule.Batch(boundaries[0], boundaries[^1]));

        Assert.Equal(goldenCase.Expect.Windows, windows);
        Assert.Equal(goldenCase.Expect.Combined, combined);

        // The tiling property itself, asserted against this core's own output
        // rather than against the vector — so a chain whose vector was somehow
        // regenerated from a broken implementation still fails here.
        Assert.Equal(combined, windows.SelectMany(window => window).ToList());
        Assert.NotEmpty(combined);
        Assert.Equal(combined.Count, combined.Select(message => message[1]).Distinct().Count());
    }

    private static MtcSchedule ScheduleFrom(MtcScheduleCase goldenCase)
    {
        var label = goldenCase.Label;
        var rate = SmpteFramerateExtensions.FromRawValue(goldenCase.Rate);
        var timecode = Timecode.Create(
                           Required(goldenCase.Input.Hours, label, "hours"),
                           Required(goldenCase.Input.Minutes, label, "minutes"),
                           Required(goldenCase.Input.Seconds, label, "seconds"),
                           Required(goldenCase.Input.Frames, label, "frames"),
                           rate)
                       ?? throw new InvalidDataException($"{label} does not name a valid timecode");

        return new MtcSchedule(
            timecode,
            Required(goldenCase.Input.AnchorHostTime, label, "anchorHostTime"),
            GoldenDouble.Parse(Required(goldenCase.Input.TicksPerSecond, label, "ticksPerSecond")));
    }

    /// <summary><c>[[byte, timestamp], …]</c> — the byte is already pinned by
    /// <c>golden/mtc-wire-v1.json</c>, so a mismatch here localises to the
    /// schedule.</summary>
    private static IReadOnlyList<IReadOnlyList<ulong>> Encode(IReadOnlyList<MtcSchedule.Message> messages) =>
        messages.Select(IReadOnlyList<ulong> (message) => new ulong[] { message.Byte, message.Timestamp }).ToList();

    private static int Required(int? value, string label, string field) =>
        value ?? throw new InvalidDataException($"{label} has no {field}");

    private static ulong Required(ulong? value, string label, string field) =>
        value ?? throw new InvalidDataException($"{label} has no {field}");

    private static T Required<T>(T? value, string label, string field)
        where T : class =>
        value ?? throw new InvalidDataException($"{label} has no {field}");

    private static void AssertDouble(string? expected, double actual, string label, string field)
    {
        var wanted = GoldenDouble.Parse(Required(expected, label, field));
        Assert.True(
            GoldenDouble.BitwiseEquals(wanted, actual),
            $"{label}: {field} expected {GoldenDouble.Describe(wanted)}, got {GoldenDouble.Describe(actual)}");
    }

    // MARK: - Independent pins (not read off the vectors)

    /// <summary>Mirrors <c>test_knownScheduleValues</c> on the Swift side.
    /// Hand-computed from the cadence, so a wrong C# implementation fails here
    /// even if the golden file were ever regenerated from a wrong source.</summary>
    [Fact]
    public void KnownCadence_AndTheTwoFrameConvention()
    {
        const ulong anchor = 1000;
        var start = Timecode.Create(0, 0, 59, 20, SmpteFramerate.Fps25)!.Value;
        var schedule = new MtcSchedule(start, anchor, 1_000_000_000);

        // 25 fps × 4 = 100 messages per second at nanosecond ticks.
        Assert.Equal(10_000_000.0, schedule.TicksPerQuarterFrame);
        Assert.Equal(anchor, schedule.TimestampForQuarterFrame(0));
        Assert.Equal(anchor + 80_000_000, schedule.TimestampForQuarterFrame(8));

        // Negative indices clamp rather than running backwards past the anchor.
        Assert.Equal(anchor, schedule.TimestampForQuarterFrame(-5));
        Assert.Equal(schedule.ByteForQuarterFrame(0), schedule.ByteForQuarterFrame(-5));

        // Eight messages carry one value and advance it by two frames.
        Assert.Equal(start, schedule.TimecodeForSequence(0));
        Assert.Equal(start.FrameCount + 2, schedule.TimecodeForSequence(1).FrameCount);
    }

    /// <summary>
    /// The quantise in <see cref="MtcSchedule"/> is load-bearing, not padding.
    /// Reproduces what a port without it would do and counts the damage, so the
    /// number in the contract's header is an assertion rather than a claim: over
    /// the first 200 messages at nanosecond ticks a tiled chain drops 74 at
    /// 24 fps and 66 at 30 fps, and none at 25 fps where the quarter-frame period
    /// is exactly 10 000 000 ticks.
    /// </summary>
    [Theory]
    [InlineData(SmpteFramerate.Fps24, 74)]
    [InlineData(SmpteFramerate.Fps30, 66)]
    [InlineData(SmpteFramerate.Fps25, 0)]
    public void DroppingTheQuantise_LosesMessages(SmpteFramerate rate, int expectedDropped)
    {
        const ulong anchor = 1000;
        var schedule = new MtcSchedule(
            Timecode.Create(0, 0, 59, 20, rate)!.Value, anchor, 1_000_000_000);
        var period = schedule.TicksPerQuarterFrame;

        var dropped = Enumerable.Range(0, 200).Count(index =>
        {
            var offset = (double)schedule.TimestampForQuarterFrame(index) - anchor;
            if (!(offset > 0))
            {
                return false;
            }

            // No quantise: `Ceiling` of a value a hair above the integer index
            // lands on the *next* index, so this message is never emitted.
            return (int)Math.Ceiling(offset / period) != index;
        });

        Assert.Equal(expectedDropped, dropped);
    }

    /// <summary>
    /// A coarse host clock makes every odd quarter-frame land on a <c>.5</c>
    /// tick, which is the only case that separates Swift's half-away-from-zero
    /// <c>.rounded()</c> from .NET's banker's <c>Math.Round</c> inside
    /// <c>TimestampForQuarterFrame</c>.
    /// </summary>
    [Fact]
    public void CoarseClock_RoundsHalfAwayFromZero()
    {
        const ulong anchor = 1000;
        var schedule = new MtcSchedule(
            Timecode.Create(0, 0, 59, 20, SmpteFramerate.Fps25)!.Value, anchor, 50);

        Assert.Equal(0.5, schedule.TicksPerQuarterFrame);
        Assert.Equal(anchor + 1, schedule.TimestampForQuarterFrame(1));  // 0.5 → 1, not 0
        Assert.Equal(anchor + 3, schedule.TimestampForQuarterFrame(5));  // 2.5 → 3, not 2
        Assert.Equal(0, Math.Round(0.5));                                // banker's, for contrast
        Assert.Equal(2, Math.Round(2.5));
    }

    /// <summary>A host clock that does not advance traps on macOS
    /// (<c>precondition</c>); it must fail here too rather than dividing by
    /// zero and scheduling everything at the anchor.</summary>
    [Fact]
    public void NonPositiveTicksPerSecond_Throws()
    {
        var timecode = Timecode.Create(0, 0, 0, 0, SmpteFramerate.Fps25)!.Value;
        Assert.Throws<ArgumentOutOfRangeException>(() => new MtcSchedule(timecode, 0, 0));
        Assert.Throws<ArgumentOutOfRangeException>(() => new MtcSchedule(timecode, 0, -1_000_000_000));
    }

    /// <summary>The degenerate windows, pinned independently of the vector: an
    /// empty or inverted window yields nothing, and one opening before the anchor
    /// clamps to quarter-frame 0 instead of going negative.</summary>
    [Fact]
    public void DegenerateWindows_YieldNothingOrClampToZero()
    {
        const ulong anchor = 1000;
        var schedule = new MtcSchedule(
            Timecode.Create(0, 0, 59, 20, SmpteFramerate.Fps24)!.Value, anchor, 1_000_000_000);

        Assert.Empty(schedule.Batch(anchor, anchor));
        Assert.Empty(schedule.Batch(anchor + 500, anchor + 100));
        Assert.Empty(schedule.Batch(0, anchor));
        // Half a quarter-frame past the anchor, so the clamped index 0 is inside
        // the window. A tick past it would *not* be: the quantise pulls `until`
        // back onto index 0, and `[from, until)` excludes its own upper bound.
        Assert.Empty(schedule.Batch(0, anchor + 1));
        Assert.Equal(anchor, Assert.Single(schedule.Batch(0, anchor + 5_000_000)).Timestamp);
    }
}
