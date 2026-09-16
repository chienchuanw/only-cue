namespace OnlyCue.Core.Ltc;

/// <summary>
/// A continuous LTC audio stream — successive 80-bit SMPTE frames starting at
/// <see cref="StartTimecode"/>, biphase-mark polarity threaded across the frame
/// boundaries so the concatenated output is a seamless waveform.
/// </summary>
/// <remarks>
/// <para>
/// Mirrors the Swift <c>LTCFrameStream</c> (<c>OnlyCue/LTC/LTCFrameStream.swift</c>);
/// macOS is the source of truth and <c>golden/ltc-schedule-v1.json</c> is the
/// contract.
/// </para>
/// <para>
/// Each frame is encoded from the level the previous one ended at, so no
/// transition is lost at a join. In practice the threading never changes the
/// output — every LTC frame ends at the level it started at, because parity
/// forces an even flip count — so this is a safety net rather than a live
/// correction, and the contract's <c>joins</c> windows cannot catch its removal.
/// What they do catch is a join whose polarity is <i>inverted</i>: that loses a
/// transition, which is a misread bit rather than a harmless inversion.
/// </para>
/// </remarks>
public sealed class LtcFrameStream
{
    /// <summary>Swift traps on a non-positive sample rate (<c>precondition</c>);
    /// throwing keeps a bad caller failing on both sides.</summary>
    public LtcFrameStream(Timecode startTimecode, double sampleRate, float amplitude = LtcEncoder.DefaultAmplitude)
    {
        if (!(sampleRate > 0))
        {
            throw new ArgumentOutOfRangeException(nameof(sampleRate), sampleRate, "sample rate must be positive");
        }

        StartTimecode = startTimecode;
        SampleRate = sampleRate;
        Amplitude = amplitude;
    }

    public Timecode StartTimecode { get; }
    public double SampleRate { get; }
    public float Amplitude { get; }

    public int FramesPerSecond => StartTimecode.Rate.FramesPerSecond();

    /// <summary>Samples in one LTC frame at this stream's sample rate (constant
    /// across frames — <c>round(sampleRate / fps)</c>, half away from zero).</summary>
    public int SamplesPerFrame => (int)Math.Round(SampleRate / FramesPerSecond, MidpointRounding.AwayFromZero);

    /// <summary>The timecode of the frame <paramref name="offset"/> frames after
    /// the start (negative offsets clamp to the start).</summary>
    public Timecode TimecodeAtFrameOffset(int offset) =>
        Timecode.FromFrameCount(StartTimecode.FrameCount + Math.Max(0, offset), StartTimecode.Rate);

    /// <summary>Float PCM (mono, <c>±amplitude</c>) for <paramref name="count"/>
    /// consecutive frames beginning at <see cref="StartTimecode"/>, with biphase
    /// polarity carried across the joins. Empty when <paramref name="count"/> is
    /// not positive.</summary>
    public float[] Samples(int count)
    {
        if (count <= 0)
        {
            return [];
        }

        var output = new List<float>(count * SamplesPerFrame + count);
        var level = false;
        for (var offset = 0; offset < count; offset++)
        {
            var (frameSamples, endLevel) = LtcEncoder.Samples(
                TimecodeAtFrameOffset(offset),
                SampleRate,
                Amplitude,
                level);
            output.AddRange(frameSamples);
            level = endLevel;
        }

        return output.ToArray();
    }
}
