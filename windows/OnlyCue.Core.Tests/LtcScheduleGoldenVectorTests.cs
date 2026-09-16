using OnlyCue.Core.Ltc;
using Xunit;

namespace OnlyCue.Core.Tests;

/// <summary>
/// The Windows half of the LTC scheduling contract (epic #728, M3 slice 2).
/// macOS emits <c>golden/ltc-schedule-v1.json</c> from the Swift
/// <c>LTCFrameStream</c> / <c>LTCSchedule</c>; this suite asserts the C#
/// re-implementation reproduces every case exactly.
/// </summary>
/// <remarks>
/// Slice 1 pinned every sample of a single frame. This one pins composition, so
/// PCM appears only as run lengths in a ±16-sample window around each join —
/// wide enough that a port which restarted the biphase polarity at every frame
/// boundary produces a visibly different window.
/// </remarks>
public class LtcScheduleGoldenVectorTests
{
    private static readonly LtcScheduleVector Vector = LtcScheduleVector.Load();

    /// <summary>Must match <c>LTCScheduleGolden.joinWindow</c> on the Swift side;
    /// <see cref="SeamWindow_IsTheWidthTheContractWasGeneratedAt"/> proves it.</summary>
    private const int JoinWindow = 16;

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
        Assert.Equal("ltc-schedule", Vector.Contract);
        Assert.Equal(1, Vector.Version);
        Assert.NotEmpty(Vector.Cases);
    }

    [Theory]
    [MemberData(nameof(CaseLabels))]
    public void CSharpCore_ReproducesGoldenCase(string label)
    {
        var goldenCase = Vector.Cases.Single(c => c.Label == label);

        switch (goldenCase.Op)
        {
            case "stream":
                AssertStream(goldenCase);
                break;
            case "streamTimecode":
                AssertStreamTimecode(goldenCase);
                break;
            case "schedule":
                AssertSchedule(goldenCase);
                break;
            case "buffer":
                AssertBuffer(goldenCase);
                break;
            case "bufferSeam":
                AssertBufferSeam(goldenCase);
                break;
            case "targetBufferCount":
                AssertTargetBufferCount(goldenCase);
                break;
            case "framesPerBuffer":
                AssertFramesPerBuffer(goldenCase);
                break;
            default:
                throw new InvalidDataException($"unknown golden op '{goldenCase.Op}'");
        }
    }

    private static void AssertStream(LtcScheduleCase goldenCase)
    {
        var label = goldenCase.Label;
        var stream = StreamFrom(goldenCase);
        var frameCount = Required(goldenCase.Input.FrameCount, label, "frameCount");
        var samples = stream.Samples(frameCount);

        Assert.Equal(goldenCase.Expect.SamplesPerFrame, stream.SamplesPerFrame);
        Assert.Equal(goldenCase.Expect.TotalSamples, samples.Length);
        Assert.Equal(goldenCase.Expect.FirstSampleIsHigh, IsHigh(samples.FirstOrDefault(), samples.Length > 0));
        Assert.Equal(goldenCase.Expect.LastSampleIsHigh, IsHigh(samples.LastOrDefault(), samples.Length > 0));

        var joins = Required(goldenCase.Expect.Joins, label, "joins");
        // A non-positive count must yield no samples *and* no joins, so the
        // early return is pinned rather than inferred from the empty array.
        Assert.Equal(frameCount > 0 ? frameCount - 1 : 0, joins.Count);
        var at = stream.SamplesPerFrame;
        foreach (var join in joins)
        {
            Assert.Equal(at, join.At);
            Assert.Equal(join.Runs, RunLengths(Window(samples, join.At)));
            at += stream.SamplesPerFrame;
        }
    }

    private static void AssertStreamTimecode(LtcScheduleCase goldenCase)
    {
        var stream = new LtcFrameStream(TimecodeFrom(goldenCase), 48000, LtcEncoder.DefaultAmplitude);
        var offset = Required(goldenCase.Input.FrameOffset, goldenCase.Label, "frameOffset");
        Assert.Equal(goldenCase.Expect.Timecode, stream.TimecodeAtFrameOffset(offset).DisplayString);
    }

    private static void AssertSchedule(LtcScheduleCase goldenCase)
    {
        var schedule = ScheduleFrom(goldenCase);
        Assert.Equal(goldenCase.Expect.SamplesPerBuffer, schedule.SamplesPerBuffer);
        AssertDouble(goldenCase.Expect.BufferDuration, schedule.BufferDuration, goldenCase.Label, "bufferDuration");
    }

    private static void AssertBuffer(LtcScheduleCase goldenCase)
    {
        var schedule = ScheduleFrom(goldenCase);
        var index = Required(goldenCase.Input.BufferIndex, goldenCase.Label, "bufferIndex");
        var buffer = schedule.BufferAt(index);

        Assert.Equal(goldenCase.Expect.Timecode, buffer.Timecode.DisplayString);
        Assert.Equal(goldenCase.Expect.SampleCount, buffer.Samples.Length);
        Assert.Equal(
            goldenCase.Expect.LastSampleIsHigh,
            IsHigh(buffer.Samples.LastOrDefault(), buffer.Samples.Length > 0));
        // `buffer(at:)` must agree with the parts it is assembled from, or a port
        // could pass every field above while `nextBuffer()` handed out something
        // else entirely.
        Assert.Equal(index, buffer.Index);
        Assert.Equal(schedule.TimecodeForBufferIndex(index), buffer.Timecode);
        Assert.Equal(schedule.SamplesForBufferIndex(index), buffer.Samples);
    }

    private static void AssertBufferSeam(LtcScheduleCase goldenCase)
    {
        var schedule = ScheduleFrom(goldenCase);
        var index = Required(goldenCase.Input.BufferIndex, goldenCase.Label, "bufferIndex");
        var previous = schedule.SamplesForBufferIndex(index);
        var next = schedule.SamplesForBufferIndex(index + 1);
        var seam = previous.TakeLast(JoinWindow).Concat(next.Take(JoinWindow)).ToArray();

        Assert.Equal(goldenCase.Expect.PreviousEndsHigh, IsHigh(previous.LastOrDefault(), previous.Length > 0));
        Assert.Equal(goldenCase.Expect.NextStartsHigh, IsHigh(next.FirstOrDefault(), next.Length > 0));
        Assert.Equal(goldenCase.Expect.Runs, RunLengths(seam));
    }

    private static void AssertTargetBufferCount(LtcScheduleCase goldenCase)
    {
        var label = goldenCase.Label;
        var schedule = ScheduleFrom(goldenCase);
        var elapsed = GoldenDouble.Parse(Required(goldenCase.Input.ElapsedSeconds, label, "elapsedSeconds"));
        var lead = Required(goldenCase.Input.LeadBuffers, label, "leadBuffers");
        Assert.Equal(goldenCase.Expect.Count, schedule.TargetBufferCount(elapsed, lead));
    }

    private static void AssertFramesPerBuffer(LtcScheduleCase goldenCase)
    {
        var rate = SmpteFramerateExtensions.FromRawValue(goldenCase.Rate);
        var targetSeconds = GoldenDouble.Parse(
            Required(goldenCase.Input.TargetSeconds, goldenCase.Label, "targetSeconds"));
        Assert.Equal(
            goldenCase.Expect.Frames,
            LtcSchedule.FramesPerBufferForTargetSeconds(targetSeconds, rate));
    }

    // MARK: - Construction from a case

    private static Timecode TimecodeFrom(LtcScheduleCase goldenCase)
    {
        var label = goldenCase.Label;
        var rate = SmpteFramerateExtensions.FromRawValue(goldenCase.Rate);
        return Timecode.Create(
                   Required(goldenCase.Input.Hours, label, "hours"),
                   Required(goldenCase.Input.Minutes, label, "minutes"),
                   Required(goldenCase.Input.Seconds, label, "seconds"),
                   Required(goldenCase.Input.Frames, label, "frames"),
                   rate)
               ?? throw new InvalidDataException($"{label} does not name a valid timecode");
    }

    private static LtcFrameStream StreamFrom(LtcScheduleCase goldenCase) =>
        new(TimecodeFrom(goldenCase), SampleRateFrom(goldenCase), AmplitudeFrom(goldenCase));

    private static LtcSchedule ScheduleFrom(LtcScheduleCase goldenCase) =>
        new(
            TimecodeFrom(goldenCase),
            SampleRateFrom(goldenCase),
            Required(goldenCase.Input.FramesPerBuffer, goldenCase.Label, "framesPerBuffer"),
            AmplitudeFrom(goldenCase));

    private static double SampleRateFrom(LtcScheduleCase goldenCase) =>
        GoldenDouble.Parse(Required(goldenCase.Input.SampleRate, goldenCase.Label, "sampleRate"));

    private static float AmplitudeFrom(LtcScheduleCase goldenCase) =>
        (float)GoldenDouble.Parse(Required(goldenCase.Input.Amplitude, goldenCase.Label, "amplitude"));

    /// <summary>A field the op requires. Missing means the vector and this
    /// verifier disagree about the contract, which is a data error rather than a
    /// mismatch — hence the throw instead of an assertion.</summary>
    private static int Required(int? value, string label, string field) =>
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

    /// <summary>`null` only when there is no sample to ask about, so an empty
    /// stream is distinguishable from one that starts low.</summary>
    private static bool? IsHigh(float sample, bool present) => present ? sample > 0 : null;

    /// <summary>The ±<see cref="JoinWindow"/> slice centred on
    /// <paramref name="index"/>, clipped to the array — the same window the Swift
    /// generator writes.</summary>
    private static float[] Window(IReadOnlyList<float> samples, int index)
    {
        var lower = Math.Max(0, index - JoinWindow);
        var upper = Math.Min(samples.Count, index + JoinWindow);
        return lower < upper ? samples.Skip(lower).Take(upper - lower).ToArray() : [];
    }

    /// <summary>Run-length encodes a <c>±amplitude</c> signal the way the contract
    /// spells it: <c>[[sign, sampleCount], …]</c>. Identical to slice 1's.</summary>
    private static List<IReadOnlyList<int>> RunLengths(IReadOnlyList<float> samples)
    {
        var runs = new List<IReadOnlyList<int>>();
        foreach (var sample in samples)
        {
            var sign = sample < 0 ? -1 : 1;
            if (runs.Count > 0 && runs[^1][0] == sign)
            {
                runs[^1] = new[] { sign, runs[^1][1] + 1 };
            }
            else
            {
                runs.Add(new[] { sign, 1 });
            }
        }

        return runs;
    }

    // MARK: - Independent pins (not read off the vectors)

    /// <summary>
    /// Mirrors <c>test_knownScheduleValues</c> on the Swift side. Hand-computed,
    /// so a wrong C# implementation fails here even if the golden file were ever
    /// regenerated from a wrong source.
    /// </summary>
    [Fact]
    public void SamplesPerBuffer_RoundsPerFrameThenMultiplies()
    {
        var schedule = new LtcSchedule(
            Timecode.Create(1, 0, 0, 0, SmpteFramerate.Fps24)!.Value, 44100, 4);

        Assert.Equal(7352, schedule.SamplesPerBuffer);
        Assert.NotEqual(
            7352,
            (int)Math.Round(4 * 44100.0 / 24.0, MidpointRounding.AwayFromZero)); // 7350 — the trap
        Assert.Equal(7352, schedule.SamplesForBufferIndex(0).Length);
        Assert.Equal(4.0 / 24.0, schedule.BufferDuration);
    }

    /// <summary>
    /// 0.1 s at 25 fps is 2.5 frames and 0.5 s is 12.5. .NET's default
    /// <c>Math.Round</c> is banker's, which lands on the even neighbour — 2 and 12
    /// — while Swift's <c>.rounded()</c> goes away from zero. 0.3 s is 7.5, where
    /// both modes give 8: the control that proves a failure is about the tie and
    /// not about ties in general.
    /// </summary>
    [Fact]
    public void FramesPerBuffer_RoundsHalfAwayFromZero()
    {
        Assert.Equal(2.5, 0.1 * 25.0);
        Assert.Equal(12.5, 0.5 * 25.0);

        Assert.Equal(3, LtcSchedule.FramesPerBufferForTargetSeconds(0.1, SmpteFramerate.Fps25));
        Assert.Equal(13, LtcSchedule.FramesPerBufferForTargetSeconds(0.5, SmpteFramerate.Fps25));
        Assert.Equal(8, LtcSchedule.FramesPerBufferForTargetSeconds(0.3, SmpteFramerate.Fps25));
        Assert.Equal(2, Math.Round(2.5));   // banker's — what the naive port writes
        Assert.Equal(12, Math.Round(12.5));

        // The `max(1, …)` floor: a buffer of no frames would stall the engine.
        Assert.Equal(1, LtcSchedule.FramesPerBufferForTargetSeconds(-1, SmpteFramerate.Fps25));
        Assert.Equal(1, LtcSchedule.FramesPerBufferForTargetSeconds(0, SmpteFramerate.Fps25));
    }

    /// <summary><c>ceil</c>, not <c>round</c>: a fifth of a buffer of playback
    /// still needs a whole buffer scheduled, and rounding would starve the
    /// engine.</summary>
    [Fact]
    public void TargetBufferCount_CeilsAndClampsBothArguments()
    {
        var schedule = new LtcSchedule(
            Timecode.Create(1, 0, 0, 0, SmpteFramerate.Fps25)!.Value, 48000, 4);

        Assert.Equal(0.16, schedule.BufferDuration);
        Assert.Equal(1, schedule.TargetBufferCount(0.2 * schedule.BufferDuration, 0));
        Assert.Equal(0, schedule.TargetBufferCount(0, 0));
        Assert.Equal(0, schedule.TargetBufferCount(-1, -1));
        Assert.Equal(2, schedule.TargetBufferCount(-1, 2));
    }

    /// <summary>
    /// The seam window is a constant on both sides; if they ever disagree the
    /// comparison would be between different slices of the same signal and would
    /// fail for the wrong reason. Read back off the contract rather than trusted.
    /// </summary>
    [Fact]
    public void SeamWindow_IsTheWidthTheContractWasGeneratedAt()
    {
        var seams = Vector.Cases.Where(c => c.Op == "bufferSeam").ToList();
        Assert.NotEmpty(seams);
        foreach (var seam in seams)
        {
            var runs = seam.Expect.Runs ?? throw new InvalidDataException($"{seam.Label} has no runs");
            Assert.Equal(2 * JoinWindow, runs.Sum(run => run[1]));
        }
    }

    /// <summary>Swift traps on a non-positive sample rate and on a buffer of fewer
    /// than one frame (<c>precondition</c>); both must fail here too rather than
    /// quietly producing an empty or nonsensical buffer.</summary>
    [Fact]
    public void DegenerateConstructorArguments_Throw()
    {
        var timecode = Timecode.Create(0, 0, 0, 0, SmpteFramerate.Fps25)!.Value;

        Assert.Throws<ArgumentOutOfRangeException>(() => new LtcFrameStream(timecode, 0));
        Assert.Throws<ArgumentOutOfRangeException>(() => new LtcFrameStream(timecode, -48000));
        Assert.Throws<ArgumentOutOfRangeException>(() => new LtcSchedule(timecode, 0, 4));
        Assert.Throws<ArgumentOutOfRangeException>(() => new LtcSchedule(timecode, 48000, 0));
        Assert.Throws<ArgumentOutOfRangeException>(() => new LtcSchedule(timecode, 48000, -1));
    }

    /// <summary><c>nextBuffer()</c> walks the same indices <c>buffer(at:)</c>
    /// exposes — the sequencing the audio callback actually uses, which no vector
    /// op covers because it is stateful.</summary>
    [Fact]
    public void NextBuffer_WalksTheIndicesInOrder()
    {
        var schedule = new LtcSchedule(
            Timecode.Create(1, 0, 0, 0, SmpteFramerate.Fps24)!.Value, 48000, 2);

        Assert.Equal(0, schedule.EmittedBuffers);
        for (var index = 0; index < 3; index++)
        {
            var buffer = schedule.NextBuffer();
            Assert.Equal(index, buffer.Index);
            Assert.Equal(schedule.TimecodeForBufferIndex(index), buffer.Timecode);
            Assert.Equal(index + 1, schedule.EmittedBuffers);
        }
    }
}
