using OnlyCue.Core.Ltc;
using Xunit;

namespace OnlyCue.Core.Tests;

/// <summary>
/// The Windows half of the LTC <b>decoder</b> contract (epic #728, M3 slice 3).
/// macOS emits <c>golden/ltc-decode-v1.json</c> from the Swift <c>LTCDecoder</c>;
/// this suite asserts the C# re-implementation reproduces every case exactly.
/// </summary>
/// <remarks>
/// <para>
/// Slices 1 and 2 pinned what OnlyCue <i>emits</i>. This one pins what it
/// <i>believes when it reads</i>, which is the harder half: a decoder that is
/// subtly wrong still returns plausible timecode on a clean signal and only
/// diverges at the edges.
/// </para>
/// <para>
/// The pipeline is pinned stage by stage rather than only end to end, so a
/// failure localises to a stage instead of every hazard failing as "decode
/// returned the wrong frames".
/// </para>
/// </remarks>
public class LtcDecodeGoldenVectorTests
{
    private static readonly LtcDecodeVector Vector = LtcDecodeVector.Load();

    /// <summary>Must match <c>LTCDecodeGolden.edgeTransitions</c> / <c>edgeBits</c>
    /// on the Swift side; <see cref="EdgeWidths_AreTheWidthsTheContractWasGeneratedAt"/>
    /// proves it rather than trusting it.</summary>
    private const int EdgeTransitions = 8;

    private const int EdgeBits = 96;

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
        Assert.Equal("ltc-decode", Vector.Contract);
        Assert.Equal(1, Vector.Version);
        Assert.NotEmpty(Vector.Cases);
    }

    [Theory]
    [MemberData(nameof(CaseLabels))]
    public void CSharpCore_ReproducesGoldenCase(string label)
    {
        var goldenCase = Vector.Cases.Single(c => c.Label == label);
        var samples = LtcDecodeRecipe.Samples(goldenCase.Input);
        var sampleRate = LtcDecodeRecipe.SampleRateOf(goldenCase.Input);

        // The recipe's own fingerprint. If the two sides build different buffers
        // this fails first and loudly, instead of surfacing three stages later.
        Assert.Equal(goldenCase.Expect.SampleCount, samples.Length);

        switch (goldenCase.Op)
        {
            case "transitions":
                AssertTransitions(goldenCase, samples);
                break;
            case "halfBit":
                AssertHalfBit(goldenCase, samples, sampleRate);
                break;
            case "framesPerSecond":
                AssertFramesPerSecond(goldenCase, samples, sampleRate);
                break;
            case "bits":
                AssertBits(goldenCase, samples, sampleRate);
                break;
            case "decode":
                AssertDecode(goldenCase, samples, sampleRate);
                break;
            default:
                throw new InvalidDataException($"unknown golden op '{goldenCase.Op}'");
        }
    }

    private static void AssertTransitions(LtcDecodeCase goldenCase, float[] samples)
    {
        var label = goldenCase.Label;
        var transitions = LtcDecoder.TransitionIndices(samples);

        Assert.Equal(Required(goldenCase.Expect.TransitionCount, label, "transitionCount"), transitions.Count);
        Assert.Equal(
            Required(goldenCase.Expect.FirstTransitions, label, "firstTransitions"),
            transitions.Take(EdgeTransitions));
        Assert.Equal(
            Required(goldenCase.Expect.LastTransitions, label, "lastTransitions"),
            transitions.TakeLast(EdgeTransitions));
    }

    private static void AssertHalfBit(LtcDecodeCase goldenCase, float[] samples, double sampleRate)
    {
        var pipeline = PipelineOf(samples, sampleRate);
        var expected = GoldenDouble.ParseOrNull(goldenCase.Expect.HalfBitSamples);
        Assert.True(
            GoldenDouble.BitwiseEquals(expected, pipeline.HalfBitSamples),
            $"{goldenCase.Label}: halfBitSamples expected {GoldenDouble.Describe(expected)}, "
            + $"got {GoldenDouble.Describe(pipeline.HalfBitSamples)}");
    }

    private static void AssertFramesPerSecond(LtcDecodeCase goldenCase, float[] samples, double sampleRate) =>
        Assert.Equal(goldenCase.Expect.FramesPerSecond, PipelineOf(samples, sampleRate).FramesPerSecond);

    private static void AssertBits(LtcDecodeCase goldenCase, float[] samples, double sampleRate)
    {
        var label = goldenCase.Label;
        var bits = PipelineOf(samples, sampleRate).Bits ?? [];

        Assert.Equal(Required(goldenCase.Expect.BitCount, label, "bitCount"), bits.Count);
        Assert.Equal(Required(goldenCase.Expect.FirstBits, label, "firstBits"), BitString(bits.Take(EdgeBits)));
        Assert.Equal(Required(goldenCase.Expect.LastBits, label, "lastBits"), BitString(bits.TakeLast(EdgeBits)));
    }

    private static void AssertDecode(LtcDecodeCase goldenCase, float[] samples, double sampleRate)
    {
        var expected = Required(goldenCase.Expect.Frames, goldenCase.Label, "frames");
        var actual = LtcDecoder.Decode(samples, sampleRate)
            .Select(frame => new LtcDecodeFrame(frame.Timecode.DisplayString, frame.StartSample))
            .ToList();
        Assert.Equal(expected, actual);
    }

    // MARK: - The pipeline, run in Decode's own order and with Decode's own guards

    private readonly record struct Pipeline(
        IReadOnlyList<int> Transitions,
        double? HalfBitSamples,
        int? FramesPerSecond,
        IReadOnlyList<bool>? Bits);

    /// <summary>
    /// Mirrors <c>LTCDecodeGolden.pipeline(of:sampleRate:)</c>. The
    /// <c>Count &lt; 3</c> bail comes <i>before</i> the half-bit estimate, exactly
    /// as in <see cref="LtcDecoder.Decode"/>, so a <c>null</c> in the vector means
    /// "the pipeline stopped here" rather than "the generator chose not to ask".
    /// </summary>
    private static Pipeline PipelineOf(IReadOnlyList<float> samples, double sampleRate)
    {
        var transitions = LtcDecoder.TransitionIndices(samples);
        if (transitions.Count < 3 || LtcDecoder.EstimateHalfBitSamples(transitions) is not { } halfBit)
        {
            return new Pipeline(transitions, null, null, null);
        }

        return new Pipeline(
            transitions,
            halfBit,
            LtcDecoder.FramesPerSecond(sampleRate, halfBit),
            LtcDecoder.Demodulate(transitions, halfBit).Bits);
    }

    private static string BitString(IEnumerable<bool> bits) =>
        string.Concat(bits.Select(bit => bit ? '1' : '0'));

    /// <summary>A field the op requires. Missing means the vector and this verifier
    /// disagree about the contract, which is a data error rather than a
    /// mismatch — hence the throw instead of an assertion.</summary>
    private static int Required(int? value, string label, string field) =>
        value ?? throw new InvalidDataException($"{label} has no {field}");

    private static T Required<T>(T? value, string label, string field)
        where T : class =>
        value ?? throw new InvalidDataException($"{label} has no {field}");

    private static IEnumerable<LtcDecodeCase> CasesFor(string op, string signal) =>
        Vector.Cases.Where(c => c.Op == op && c.Label.StartsWith($"{op}/{signal}", StringComparison.Ordinal));

    private static LtcDecodeCase CaseFor(string op, string signal) => CasesFor(op, signal).Single();

    /// <summary>
    /// Mirrors the Swift <c>withoutTheCorruptedFrames</c>. The expectation for a
    /// corrupted run is "the control run, minus exactly the frames the mutations
    /// land on" — derived from <c>flips</c> rather than written down as positional
    /// indices, so the assertion survives a change to the run length and still
    /// fails if a neighbour shifts by a single sample. The
    /// <c>control must decode</c> guard is what keeps this from degenerating into
    /// "the control never decoded that frame either, so of course nothing changed".
    /// </summary>
    private static List<LtcDecodeFrame> WithoutTheCorruptedFrames(
        List<LtcDecodeFrame> control,
        LtcDecodeCase goldenCase)
    {
        var input = goldenCase.Input;
        var start = LtcDecodeRecipe.StartOf(input);
        var rate = LtcDecodeRecipe.RateOf(input);
        var flips = Required(input.Flips, goldenCase.Label, "flips");
        Assert.NotEmpty(flips);

        var corrupted = flips
            .Select(flip => Timecode.FromFrameCount(start.FrameCount + flip.Frame, rate).DisplayString)
            .ToHashSet();
        foreach (var timecode in corrupted)
        {
            Assert.True(
                control.Any(frame => frame.Timecode == timecode),
                $"the control must decode {timecode} or the case proves nothing");
        }

        return control.Where(frame => !corrupted.Contains(frame.Timecode)).ToList();
    }

    // MARK: - Independent pins (hand-derived, not read off the vectors)

    /// <summary>
    /// <b>The first latch is not a transition.</b> The comparator starts at
    /// <c>state == 0</c> and the first latch sets the state <i>without</i>
    /// recording an index — so a signal that opens high has no transition at
    /// sample 0, and every start sample in the contract is measured from the first
    /// real sign change. A port that records the first latch shifts every index by
    /// one position and every start sample to 0.
    /// </summary>
    [Fact]
    public void FirstLatch_IsNotATransition()
    {
        Assert.Equal(new[] { 1, 2, 3 }, LtcDecoder.TransitionIndices([0.8f, -0.8f, 0.8f, -0.8f]));
        Assert.Equal(new[] { 1, 2 }, LtcDecoder.TransitionIndices([-0.8f, 0.8f, -0.8f]));
    }

    /// <summary>
    /// <b>The half-bit cluster, hand-derived.</b> At 24 fps / 48 kHz a half-bit
    /// slot is exactly 12.5 samples, so the slot boundaries <c>round(k × 12.5)</c>
    /// alternate 13 and 12 samples long. Biphase mark puts a transition at every
    /// bit boundary and one more in the middle of every <c>1</c>, so the only
    /// inter-transition intervals that can occur are <b>13 then 12</b> (the two
    /// halves of a <c>1</c>) and <b>25</b> (a whole <c>0</c>).
    /// <para>
    /// The estimate takes the minimum (12), keeps everything <i>strictly</i> below
    /// <c>1.5 × 12 = 18</c>, and averages. So the cluster is exactly the 12s and
    /// the 13s, the 25s are excluded, and the mean lands on 12.5 up to the single
    /// unpaired 13 at the end of the buffer. <c>&lt;=</c> instead of <c>&lt;</c>,
    /// or a median, or an integer mean, moves it.
    /// </para>
    /// </summary>
    [Fact]
    public void HalfBitCluster_IsExactlyTheTwelveAndThirteenSampleIntervals()
    {
        var samples = LtcDecodeRecipe.Samples(CaseFor("transitions", "clean/24@48000").Input);
        var transitions = LtcDecoder.TransitionIndices(samples);
        var intervals = transitions.Skip(1).Zip(transitions, (next, previous) => next - previous).ToList();

        Assert.Equal(new[] { 12, 13, 25 }, intervals.Distinct().Order());
        var cluster = intervals.Where(interval => interval < 18).ToList();
        Assert.Equal(new[] { 12, 13 }, cluster.Distinct().Order());
        Assert.Equal(intervals.Count - intervals.Count(interval => interval == 25), cluster.Count);

        var halfBit = LtcDecoder.EstimateHalfBitSamples(transitions);
        Assert.NotNull(halfBit);
        Assert.Equal((double)cluster.Sum() / cluster.Count, halfBit.Value);
        Assert.Equal(12.5, halfBit.Value, 0.01);
        Assert.Equal(24, LtcDecoder.FramesPerSecond(48000, halfBit.Value));
    }

    /// <summary>
    /// <b>A parity-broken frame is consumed, so the frames after it keep their
    /// offsets.</b> <c>ExtractFrames</c> advances 80 bits on a <i>sync match</i>,
    /// not on a <i>valid frame</i>, so the assertion is not "one frame is missing"
    /// but that every other frame comes back at a byte-identical start sample.
    /// <para>
    /// <b>What this case does not prove.</b> An earlier version of this remark
    /// claimed it catches a port which puts the advance inside the validity check.
    /// Mutation testing falsified that: such a port, and one that never skips at
    /// all, both crawl bit-by-bit through the broken frame, re-lock on the
    /// <i>next</i> real sync word, and return this exact list. With sync words only
    /// at frame boundaries there is nothing for them to re-lock on wrongly. That is
    /// what <see cref="PlantedSyncWord_IsSkipped_BecauseTheAdvanceIsEightyBits"/>
    /// is for.
    /// </para>
    /// </summary>
    [Fact]
    public void ParityBrokenFrame_IsConsumed_SoLaterFramesKeepTheirOffsets()
    {
        var corrupted = CaseFor("decode", "parity-flipped-middle-frame");
        var control = Decode(CaseFor("decode", "clean/24@48000"));

        Assert.True(control.Count >= 3, "the corrupted frame needs neighbours on both sides");
        Assert.Equal(WithoutTheCorruptedFrames(control, corrupted), Decode(corrupted));
    }

    /// <summary>
    /// <b>The advance really is 80 bits — the case mutation testing forced.</b>
    /// <c>spurious-sync-after-a-broken-frame</c> breaks one frame's parity
    /// <i>and</i> plants a sync word inside the next frame's payload. The planted
    /// word makes the 80-bit window ending on it a syntactically complete,
    /// well-formed, in-range frame that straddles the two real frames and is
    /// aligned to neither — a frame that was never transmitted.
    /// <para>
    /// The real decoder never sees it: it matches the broken frame's sync, advances
    /// a whole 80 bits, and lands past the trap. A decoder that advances only on a
    /// <i>valid</i> frame, or one that always advances a single bit, walks into it
    /// and reports the phantom. Both are green on every other case in this
    /// contract.
    /// </para>
    /// </summary>
    [Fact]
    public void PlantedSyncWord_IsSkipped_BecauseTheAdvanceIsEightyBits()
    {
        const int BitsPerFrame = 80;
        var goldenCase = CaseFor("decode", "spurious-sync-after-a-broken-frame");
        var samples = LtcDecodeRecipe.Samples(goldenCase.Input);
        var sampleRate = LtcDecodeRecipe.SampleRateOf(goldenCase.Input);

        // The trap is really on the wire, and off the frame grid. The demodulated
        // stream does not begin on a frame boundary (the comparator's first latch
        // is not a transition), so the grid is read off the stream rather than
        // assumed: the real sync words all share one residue mod 80, and the plant
        // is the single one that does not.
        var bits = PipelineOf(samples, sampleRate).Bits ?? [];
        var matches = Enumerable.Range(0, bits.Count - LtcFrame.SyncWord.Count + 1)
            .Where(start => bits.Skip(start).Take(LtcFrame.SyncWord.Count).SequenceEqual(LtcFrame.SyncWord))
            .ToList();
        Assert.NotEmpty(matches);

        var grid = matches.GroupBy(start => start % BitsPerFrame)
            .OrderByDescending(group => group.Count())
            .First().Key;
        var offGrid = matches.Where(start => start % BitsPerFrame != grid).ToList();
        Assert.Single(offGrid);  // exactly one sync word off the frame grid: the plant

        // And the decoder steps straight over it: what survives is the control run
        // minus the two frames the flips land on, and nothing else.
        var control = Decode(CaseFor("decode", "clean/24@48000"));
        var decoded = Decode(goldenCase);
        Assert.Equal(WithoutTheCorruptedFrames(control, goldenCase), decoded);
        Assert.DoesNotContain(decoded, frame => frame.Timecode == "00:00:45:00");
    }

    /// <summary>
    /// <b>A well-formed word can still name no timecode.</b> The
    /// <c>bcd-out-of-range</c> recipe drives the frames field out of range and flips
    /// the parity position back, so the word passes
    /// <see cref="LtcFrame.IsWellFormed"/> and is refused only by
    /// <see cref="LtcFrame.ToTimecode"/>. Validity and range are two gates; a port
    /// that folds them into one passes every clean case and fails here.
    /// <para>
    /// The word is rebuilt from the frame the mutation actually lands on (the
    /// single entry in <c>flips</c>), not from the run's first frame — otherwise
    /// this would pin arithmetic that never reaches the wire.
    /// </para>
    /// </summary>
    [Fact]
    public void BcdOutOfRange_IsWellFormedButNamesNoTimecode()
    {
        var goldenCase = CaseFor("decode", "bcd-out-of-range");
        var input = goldenCase.Input;
        var start = LtcDecodeRecipe.StartOf(input);
        var flip = Assert.Single(Required(input.Flips, goldenCase.Label, "flips"));
        var rate = LtcDecodeRecipe.RateOf(input);
        var bits = LtcFrame
            .FromTimecode(Timecode.FromFrameCount(start.FrameCount + flip.Frame, rate))
            .Bits.ToArray();
        foreach (var index in flip.Indices)
        {
            bits[index] = !bits[index];
        }

        var frame = LtcFrame.FromBits(bits);
        Assert.True(frame.IsWellFormed);  // an even number of flips preserves parity
        Assert.Equal(33, frame.Frames);   // no rate in the matrix has a frame 33
        Assert.Null(frame.ToTimecode(24));

        // Refused at the range gate, not the validity gate — so, exactly as with a
        // broken parity, only that frame goes missing.
        var control = Decode(CaseFor("decode", "clean/24@48000"));
        Assert.Equal(WithoutTheCorruptedFrames(control, goldenCase), Decode(goldenCase));
    }

    /// <summary>
    /// <b>The DC ladder straddles a root, and the root is algebra rather than a
    /// golden number.</b> The comparator is symmetric about zero and there is no DC
    /// blocker, so an offset <c>D</c> on a <c>±A</c> square wave moves the samples
    /// to <c>D ± A</c> while the reference RMS becomes <c>√(D² + A²)</c>. The
    /// negative latch stops firing — and the decode collapses to nothing — once
    /// <c>A − D &lt; 0.3·√(D² + A²)</c>, which at <c>A = 0.8</c> solves to
    /// <c>D ≈ 0.51462</c>.
    /// <para>
    /// Pinning the collapse rather than assuming it is the point: a port that
    /// "helpfully" adds a DC blocker decodes every rung and fails the top two.
    /// </para>
    /// </summary>
    [Fact]
    public void DcLadder_StraddlesTheLatchRoot()
    {
        var amplitude = (double)LtcEncoder.DefaultAmplitude;
        bool Latches(double offset) =>
            amplitude - offset >= 0.3 * Math.Sqrt((offset * offset) + (amplitude * amplitude));

        Assert.True(Latches(0.5));
        Assert.False(Latches(0.55));

        var ladder = CasesFor("decode", "dc-offset/").ToList();
        Assert.Equal(3, ladder.Count);
        foreach (var goldenCase in ladder)
        {
            var offset = GoldenDouble.Parse(Required(goldenCase.Input.OffsetBy, goldenCase.Label, "offsetBy"));
            Assert.Equal(!Latches(offset), Decode(goldenCase).Count == 0);
        }
    }

    /// <summary>
    /// <b>The silence floor's position, not merely its existence.</b> The signal is
    /// a square wave at <c>±amplitude</c>, so its RMS <i>is</i> the amplitude; the
    /// ladder puts rungs either side of <see cref="LtcDecoder.SilenceRmsFloor"/>
    /// with one sitting exactly <i>on</i> it — which is what pins <c>&gt;=</c>
    /// rather than <c>&gt;</c>.
    /// </summary>
    [Fact]
    public void SilenceFloorLadder_StraddlesTheFloor()
    {
        Assert.Equal(1e-4f, LtcDecoder.SilenceRmsFloor);

        var ladder = CasesFor("transitions", "silence-floor/").ToList();
        Assert.Equal(4, ladder.Count);
        foreach (var goldenCase in ladder)
        {
            var amplitude = LtcDecodeRecipe.AmplitudeOf(goldenCase.Input);
            var transitions = LtcDecoder.TransitionIndices(LtcDecodeRecipe.Samples(goldenCase.Input));
            Assert.Equal(
                amplitude < LtcDecoder.SilenceRmsFloor,
                transitions.Count == 0);
        }
    }

    /// <summary>
    /// The recipe builder has to reproduce the production stream exactly when no
    /// mutation is asked for, or every clean case pins the builder rather than the
    /// decoder. "No mutation" is read off the input fields, not off the label, so a
    /// new clean case is covered automatically.
    /// </summary>
    [Fact]
    public void UnmutatedRecipe_IsTheProductionFrameStream()
    {
        var clean = Vector.Cases
            .Where(c => c.Op == "decode")
            .Select(c => c.Input)
            .Where(input => input.FrameCount > 0
                            && input.LeadSilenceSamples == 0
                            && input.TrailSilenceSamples == 0
                            && input.TruncateToSamples is null
                            && input.Flips is null
                            && input.OffsetBy is null)
            .ToList();

        Assert.NotEmpty(clean);
        foreach (var input in clean)
        {
            var stream = new LtcFrameStream(
                LtcDecodeRecipe.StartOf(input),
                LtcDecodeRecipe.SampleRateOf(input),
                LtcDecodeRecipe.AmplitudeOf(input));
            Assert.Equal(stream.Samples(input.FrameCount), LtcDecodeRecipe.Samples(input));
        }
    }

    /// <summary>
    /// The edge widths are constants on both sides; if they ever disagree the
    /// comparison would be between different slices of the same list and would fail
    /// for the wrong reason. Read back off the contract rather than trusted.
    /// </summary>
    [Fact]
    public void EdgeWidths_AreTheWidthsTheContractWasGeneratedAt()
    {
        var transitions = Vector.Cases.Where(c => c.Op == "transitions").ToList();
        Assert.NotEmpty(transitions);
        foreach (var goldenCase in transitions)
        {
            var count = Required(goldenCase.Expect.TransitionCount, goldenCase.Label, "transitionCount");
            var first = Required(goldenCase.Expect.FirstTransitions, goldenCase.Label, "firstTransitions");
            var last = Required(goldenCase.Expect.LastTransitions, goldenCase.Label, "lastTransitions");
            Assert.Equal(Math.Min(EdgeTransitions, count), first.Count);
            Assert.Equal(Math.Min(EdgeTransitions, count), last.Count);
        }

        var bits = Vector.Cases.Where(c => c.Op == "bits").ToList();
        Assert.NotEmpty(bits);
        foreach (var goldenCase in bits)
        {
            var count = Required(goldenCase.Expect.BitCount, goldenCase.Label, "bitCount");
            Assert.Equal(
                Math.Min(EdgeBits, count),
                Required(goldenCase.Expect.FirstBits, goldenCase.Label, "firstBits").Length);
            Assert.Equal(
                Math.Min(EdgeBits, count),
                Required(goldenCase.Expect.LastBits, goldenCase.Label, "lastBits").Length);
        }
    }

    /// <summary>Swift traps on a non-positive sample rate (<c>precondition</c>) and
    /// on a word that is not 80 bits; both must fail here too rather than quietly
    /// returning nothing.</summary>
    [Fact]
    public void DegenerateArguments_Throw()
    {
        Assert.Throws<ArgumentOutOfRangeException>(() => LtcDecoder.Decode([], 0));
        Assert.Throws<ArgumentOutOfRangeException>(() => LtcDecoder.Decode([], -48000));
        Assert.Throws<ArgumentException>(() => LtcFrame.FromBits(new bool[79]));
    }

    private static List<LtcDecodeFrame> Decode(LtcDecodeCase goldenCase) =>
        LtcDecoder.Decode(
                LtcDecodeRecipe.Samples(goldenCase.Input),
                LtcDecodeRecipe.SampleRateOf(goldenCase.Input))
            .Select(frame => new LtcDecodeFrame(frame.Timecode.DisplayString, frame.StartSample))
            .ToList();
}
