namespace OnlyCue.Core.Ltc;

/// <summary>
/// Recovers SMPTE timecode from a stream of LTC audio samples — the inverse of
/// <see cref="LtcEncoder"/> / <see cref="LtcFrameStream"/>. Pure: feed it mono
/// <c>float</c> samples + the sample rate, get back the timecodes it found and
/// where (in samples) each frame began.
/// </summary>
/// <remarks>
/// <para>
/// Mirrors the Swift <c>LTCDecoder</c> (<c>OnlyCue/LTC/LTCDecoder.swift</c>);
/// macOS is the source of truth and <c>golden/ltc-decode-v1.json</c> is the
/// contract.
/// </para>
/// <para>
/// Pipeline: zero-crossing detection → biphase-mark demodulation (a bit boundary
/// at every transition; a <c>1</c> adds a mid-bit transition, so a <c>0</c> spans
/// one bit period and a <c>1</c> spans two half-bit intervals) → sliding 80-bit
/// window → lock when the trailing 16 bits are the sync word → validate (sync +
/// even parity + in-range BCD fields) → <see cref="Timecode"/>. The bit period is
/// estimated from the transition-interval histogram, so the framerate is
/// recovered, not assumed.
/// </para>
/// <para>
/// <b>Arithmetic width is part of the contract, not an implementation detail.</b>
/// The RMS accumulates in <c>double</c> and narrows once at the end; the
/// comparator threshold is then a <c>float</c> product compared against
/// <c>float</c> samples. Widening either to <c>double</c> throughout moves the
/// latch on samples that sit within an ulp of the threshold — which is exactly
/// what the vectors' DC-offset ladder walks up to.
/// </para>
/// <para>
/// The intermediate stages are <c>internal</c> rather than private so the golden
/// vectors can pin each one on its own: with only <see cref="Decode"/> to assert
/// on, every hazard in the pipeline fails the same way and a mutation cannot tell
/// a broken comparator from a broken framer. They are not product API.
/// </para>
/// </remarks>
public static class LtcDecoder
{
    /// <summary>A buffer whose RMS falls below this carries no signal worth
    /// decoding. See the Swift original for the measurements behind the value
    /// (#793); the comparison is <c>&gt;=</c>, so a buffer sitting exactly on the
    /// floor still decodes.</summary>
    internal const float SilenceRmsFloor = 1e-4f;

    /// <summary>Fraction of the reference amplitude at which the comparator
    /// latches. <c>internal</c> so <c>LtcDecoderMutationEquivalenceTests</c> can
    /// measure the exact threshold the comparator uses rather than a copy of
    /// it.</summary>
    internal const float ThresholdFraction = 0.3f;

    /// <summary>One recovered frame: the timecode and the sample index where its
    /// first bit started.</summary>
    public readonly record struct DecodedFrame(Timecode Timecode, int StartSample);

    /// <summary>Decode every well-formed LTC frame in <paramref name="samples"/>.
    /// Empty if the signal is too short / noisy to lock.</summary>
    /// <remarks>Swift traps on a non-positive sample rate (<c>precondition</c>);
    /// throwing keeps a bad caller failing on both sides.</remarks>
    public static IReadOnlyList<DecodedFrame> Decode(IReadOnlyList<float> samples, double sampleRate)
    {
        if (!(sampleRate > 0))
        {
            throw new ArgumentOutOfRangeException(nameof(sampleRate), sampleRate, "sample rate must be positive");
        }

        var transitions = TransitionIndices(samples);
        if (transitions.Count < 3)
        {
            return [];
        }

        var halfBit = EstimateHalfBitSamples(transitions);
        if (halfBit is null)
        {
            return [];
        }

        var stream = Demodulate(transitions, halfBit.Value);
        return ExtractFrames(stream, FramesPerSecond(sampleRate, halfBit.Value));
    }

    /// <summary>
    /// The timeline rate implied by a measured half-bit period: 80 bits per
    /// frame, two half-bits per bit. Swift's <c>.rounded()</c> is half away from
    /// zero — the same hazard as the encoder's slot boundaries, except that here
    /// getting it wrong does not shift a sample, it returns the wrong rate or
    /// none at all.
    /// </summary>
    internal static int FramesPerSecond(double sampleRate, double halfBitSamples)
    {
        var bitRate = sampleRate / (2.0 * halfBitSamples);
        return (int)Math.Round(bitRate / 80.0, MidpointRounding.AwayFromZero);
    }

    /// <summary>
    /// Indices where the signal crosses a hysteresis comparator.
    /// </summary>
    /// <remarks>
    /// A bare zero-crossing detector has no noise immunity: the dither in a
    /// decoded mp3's silent lead-in flips sign every sample or two, which swamps
    /// the interval statistics the demodulator depends on. Latching only past
    /// ± <c>ThresholdFraction · rms</c> gates that out.
    /// <para>
    /// The reference amplitude is deliberately computed over the WHOLE buffer and
    /// must stay global. A per-block adaptive reference re-introduces the bug: a
    /// block of pure noise has an RMS equal to the noise, so its threshold
    /// collapses to the noise floor (#793).
    /// </para>
    /// <para>
    /// The first latch sets the state <i>without</i> recording an index, so a
    /// signal that opens high has no transition at sample 0 and every start
    /// sample is measured from the first real sign change.
    /// </para>
    /// </remarks>
    internal static IReadOnlyList<int> TransitionIndices(IReadOnlyList<float> samples)
    {
        var reference = Rms(samples);
        if (!(reference >= SilenceRmsFloor))
        {
            // Spelt as the negation of Swift's `guard reference >= floor` rather
            // than as `reference < floor`, so a NaN reference bails on both sides.
            return [];
        }

        var threshold = ThresholdFraction * reference;

        var indices = new List<int>();
        var state = 0;
        for (var index = 0; index < samples.Count; index++)
        {
            var sample = samples[index];
            if (state <= 0 && sample > threshold)
            {
                if (state != 0)
                {
                    indices.Add(index);
                }

                state = 1;
            }
            else if (state >= 0 && sample < -threshold)
            {
                if (state != 0)
                {
                    indices.Add(index);
                }

                state = -1;
            }
        }

        return indices;
    }

    /// <summary>
    /// Estimates the half-bit period from the shortest transition intervals.
    /// Biphase-mark encoding emits one transition per <c>0</c> bit and two per
    /// <c>1</c>, so the shortest intervals are the half-bit period; the estimate
    /// is the mean of every interval <i>strictly</i> within 1.5× of the minimum.
    /// This is only sound because <see cref="TransitionIndices"/> gates out noise
    /// first — an ungated minimum collapses to 1 sample (#793).
    /// </summary>
    internal static double? EstimateHalfBitSamples(IReadOnlyList<int> transitions)
    {
        var intervals = new List<int>(Math.Max(0, transitions.Count - 1));
        for (var index = 1; index < transitions.Count; index++)
        {
            intervals.Add(transitions[index] - transitions[index - 1]);
        }

        if (intervals.Count == 0)
        {
            return null;
        }

        var smallest = intervals.Min();
        if (smallest <= 0)
        {
            return null;
        }

        var total = 0L;
        var count = 0;
        foreach (var interval in intervals)
        {
            if (interval < 1.5 * smallest)
            {
                total += interval;
                count++;
            }
        }

        return count == 0 ? null : (double)total / count;
    }

    /// <summary>The recovered bit sequence plus, for each bit, the sample index of
    /// the transition that began it (so a frame's start can be reported in
    /// samples).</summary>
    internal readonly record struct BitStream(IReadOnlyList<bool> Bits, IReadOnlyList<int> StartSamples);

    /// <summary>
    /// Walk the transitions, classifying each inter-transition interval as a whole
    /// bit period (<c>0</c>) or a half (the first of the two halves of a <c>1</c>).
    /// Intervals that fit neither are dropped (re-sync). A <c>1</c> needs a
    /// <i>following</i> transition to be emitted at all — hence the
    /// <c>index + 1 &lt; transitions.Count</c> guard, which is what keeps a buffer
    /// cut exactly on a frame boundary from growing a phantom final bit.
    /// </summary>
    internal static BitStream Demodulate(IReadOnlyList<int> transitions, double halfBitSamples)
    {
        var bits = new List<bool>();
        var startSamples = new List<int>();
        var index = 1;
        while (index < transitions.Count)
        {
            var start = transitions[index - 1];
            var halfBits = (transitions[index] - start) / halfBitSamples;
            if (halfBits >= 1.5 && halfBits < 2.5)
            {
                bits.Add(false);
                startSamples.Add(start);
                index += 1;
            }
            else if (halfBits >= 0.5 && halfBits < 1.5 && index + 1 < transitions.Count)
            {
                // A `1` is two ~half-bit intervals; consume both.
                bits.Add(true);
                startSamples.Add(start);
                index += 2;
            }
            else
            {
                index += 1;
            }
        }

        return new BitStream(bits, startSamples);
    }

    /// <summary>
    /// Slide an 80-bit window over the bit stream; when the trailing 16 bits are
    /// the sync word, the window is a complete frame (payload bits 0–63, sync
    /// 64–79). The frame's start sample is the start of its first bit.
    /// </summary>
    /// <remarks>
    /// The window advances 80 bits on a <b>sync match</b>, not on a <b>valid
    /// frame</b> — so a frame whose parity has been broken is consumed and the
    /// search resumes cleanly after it, leaving the frames that follow at their
    /// correct start samples — pinned by the vectors'
    /// <c>parity-flipped-middle-frame</c> case.
    /// <para>
    /// That case alone does <b>not</b> catch a port that moves the advance inside
    /// the validity check, nor one that never skips at all. An earlier version of
    /// this remark claimed it did; mutation testing falsified it. With sync words
    /// only at frame boundaries, a bit-by-bit crawl through the broken frame
    /// re-locks on the next real sync word and returns an identical list. The case
    /// that separates them is <c>spurious-sync-after-a-broken-frame</c>, which
    /// plants a sync word inside the following frame's payload so a crawling
    /// decoder reports a frame that was never transmitted.
    /// </para>
    /// </remarks>
    private static IReadOnlyList<DecodedFrame> ExtractFrames(BitStream stream, int framesPerSecond)
    {
        var bits = stream.Bits;
        if (bits.Count < LtcFrame.BitCount)
        {
            return [];
        }

        var frames = new List<DecodedFrame>();
        var end = LtcFrame.BitCount;
        while (end <= bits.Count)
        {
            var window = new bool[LtcFrame.BitCount];
            for (var offset = 0; offset < LtcFrame.BitCount; offset++)
            {
                window[offset] = bits[end - LtcFrame.BitCount + offset];
            }

            if (window.Skip(64).Take(16).SequenceEqual(LtcFrame.SyncWord))
            {
                var frame = LtcFrame.FromBits(window);
                if (frame.IsWellFormed && frame.ToTimecode(framesPerSecond) is { } timecode)
                {
                    frames.Add(new DecodedFrame(timecode, stream.StartSamples[end - LtcFrame.BitCount]));
                }

                end += LtcFrame.BitCount;
            }
            else
            {
                end += 1;
            }
        }

        return frames;
    }

    /// <summary>
    /// Root-mean-square over the whole buffer. The accumulator is
    /// <c>double</c> and the result narrows once, mirroring Swift — accumulating
    /// in <c>float</c> instead loses the tail of a long buffer and shifts the
    /// threshold.
    /// </summary>
    /// <summary><c>internal</c> for the same reason as the pipeline stages: the
    /// mutation-equivalence proof needs the exact reference amplitude the
    /// comparator saw, not a re-derivation of it.</summary>
    internal static float Rms(IReadOnlyList<float> samples)
    {
        if (samples.Count == 0)
        {
            return 0;
        }

        var total = 0.0;
        foreach (var sample in samples)
        {
            total += (double)sample * sample;
        }

        return (float)Math.Sqrt(total / samples.Count);
    }
}
