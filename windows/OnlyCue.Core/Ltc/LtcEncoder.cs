namespace OnlyCue.Core.Ltc;

/// <summary>
/// Generates LTC audio: builds the 80-bit <see cref="LtcFrame"/> for a
/// <see cref="Timecode"/>, biphase-mark-modulates it, and lays the result down as
/// <c>float</c> PCM at a given sample rate.
/// </summary>
/// <remarks>
/// <para>
/// Mirrors the Swift <c>LTCEncoder.samples(for:sampleRate:amplitude:startLevel:)</c>
/// (<c>OnlyCue/LTC/LTCEncoder.swift</c>); macOS is the source of truth and
/// <c>golden/ltc-wire-v1.json</c> is the contract. The <c>AVAudioPCMBuffer</c>
/// half of the Swift type is Apple-only and has no mirror.
/// </para>
/// <para>
/// The 80-bit frame is split into 160 half-bit slots; slot <c>k</c> occupies
/// samples <c>[round(k·R) … round((k+1)·R))</c> where
/// <c>R = sampleRate / (160·fps)</c>. <c>R</c> is often fractional — at 24 fps and
/// 48 kHz it is exactly <b>12.5</b>, so every odd slot boundary is a midpoint
/// tie, and <b>the rounding rule is part of the wire format</b>. Swift's
/// <c>.rounded()</c> is half-away-from-zero; .NET's default
/// <c>Math.Round(double)</c> is banker's rounding and would place every other
/// boundary one sample early. Hence the explicit
/// <see cref="MidpointRounding.AwayFromZero"/> — it is not a style choice.
/// </para>
/// </remarks>
public static class LtcEncoder
{
    /// <summary>Standalone/test fallback amplitude. The product default lives in
    /// the routing settings and is always passed explicitly on the live path.</summary>
    public const float DefaultAmplitude = 0.8f;

    private const int HalfBitSlotsPerFrame = 160;

    /// <summary>
    /// Float PCM samples (mono, <c>±amplitude</c>) for one LTC frame at
    /// <paramref name="timecode"/>, continuous from <paramref name="startLevel"/>.
    /// Returns the samples and the signal level after the last sample, so
    /// consecutive frames can be modulated continuously.
    /// </summary>
    /// <remarks>Swift traps on a non-positive sample rate
    /// (<c>precondition</c>); throwing here keeps a bad caller failing on both
    /// sides rather than silently producing an empty buffer on one of them.</remarks>
    public static (float[] Samples, bool EndLevel) Samples(
        Timecode timecode,
        double sampleRate,
        float amplitude = DefaultAmplitude,
        bool startLevel = false)
    {
        if (!(sampleRate > 0))
        {
            throw new ArgumentOutOfRangeException(nameof(sampleRate), sampleRate, "sample rate must be positive");
        }

        var frame = LtcFrame.FromTimecode(timecode);
        var halfBitSamples = sampleRate / (HalfBitSlotsPerFrame * (double)timecode.Rate.FramesPerSecond());
        var high = amplitude;
        var low = -amplitude;

        var level = startLevel;
        var samples = new List<float>((int)Round(sampleRate / timecode.Rate.FramesPerSecond()) + 2);
        var slot = 0;

        void EmitSlot()
        {
            var start = Round(slot * halfBitSamples);
            var end = Round((slot + 1) * halfBitSamples);
            for (var count = Math.Max(0, end - start); count > 0; count--)
            {
                samples.Add(level ? high : low);
            }

            slot++;
        }

        foreach (var bit in frame.Bits)
        {
            level = !level;             // bit-boundary transition (always)
            EmitSlot();
            if (bit)
            {
                level = !level;         // mid-bit transition for a 1
            }

            EmitSlot();
        }

        return (samples.ToArray(), level);
    }

    /// <summary>Swift's <c>Double.rounded()</c>: half away from zero, then
    /// truncated to an <c>int</c>.</summary>
    private static int Round(double value) => (int)Math.Round(value, MidpointRounding.AwayFromZero);
}
