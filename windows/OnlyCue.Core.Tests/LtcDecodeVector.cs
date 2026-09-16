using System.Text.Json.Serialization;
using OnlyCue.Core.Ltc;

namespace OnlyCue.Core.Tests;

/// <summary>
/// DTO mirroring <c>LTCDecodeGoldenVector</c> in
/// <c>OnlyCueTests/LTCDecodeGolden.swift</c>. macOS is the source of truth for
/// <c>golden/ltc-decode-v1.json</c>; this side only ever reads it.
/// </summary>
public sealed record LtcDecodeVector(
    [property: JsonPropertyName("contract")] string Contract,
    [property: JsonPropertyName("version")] int Version,
    [property: JsonPropertyName("note")] string Note,
    [property: JsonPropertyName("cases")] IReadOnlyList<LtcDecodeCase> Cases)
{
    private const string RelativePath = "golden/ltc-decode-v1.json";

    public static LtcDecodeVector Load() => GoldenFiles.Load<LtcDecodeVector>(RelativePath);
}

public sealed record LtcDecodeCase(
    [property: JsonPropertyName("label")] string Label,
    [property: JsonPropertyName("op")] string Op,
    [property: JsonPropertyName("input")] LtcDecodeInput Input,
    [property: JsonPropertyName("expect")] LtcDecodeExpect Expect);

/// <summary>
/// The recipe for one signal. Signals are recipes, not sample dumps: both sides
/// build the identical buffer from these fields, in the order
/// <see cref="LtcDecodeRecipe.Samples"/> documents.
/// </summary>
public sealed record LtcDecodeInput(
    [property: JsonPropertyName("rate")] string Rate,
    [property: JsonPropertyName("sampleRate")] string SampleRate,
    [property: JsonPropertyName("amplitude")] string Amplitude,
    [property: JsonPropertyName("timecode")] IReadOnlyList<int> Timecode,
    [property: JsonPropertyName("frameCount")] int FrameCount,
    [property: JsonPropertyName("leadSilenceSamples")] int LeadSilenceSamples,
    [property: JsonPropertyName("trailSilenceSamples")] int TrailSilenceSamples,
    [property: JsonPropertyName("truncateToSamples")] int? TruncateToSamples,
    [property: JsonPropertyName("flips")] IReadOnlyList<LtcDecodeFlip>? Flips,
    [property: JsonPropertyName("offsetBy")] string? OffsetBy);

/// <summary>
/// A bit-flip mutation on one encoded frame. A list, not a single frame, because
/// the <c>spurious-sync-after-a-broken-frame</c> case needs two: one frame broken
/// and the <i>next</i> one carrying the trap.
/// </summary>
public sealed record LtcDecodeFlip(
    [property: JsonPropertyName("frame")] int Frame,
    [property: JsonPropertyName("indices")] IReadOnlyList<int> Indices);

public sealed record LtcDecodeFrame(
    [property: JsonPropertyName("timecode")] string Timecode,
    [property: JsonPropertyName("startSample")] int StartSample);

public sealed record LtcDecodeExpect(
    // Carried by every op — the recipe's own fingerprint.
    [property: JsonPropertyName("sampleCount")] int SampleCount,
    // op: "decode"
    [property: JsonPropertyName("frames")] IReadOnlyList<LtcDecodeFrame>? Frames,
    // op: "transitions"
    [property: JsonPropertyName("transitionCount")] int? TransitionCount,
    [property: JsonPropertyName("firstTransitions")] IReadOnlyList<int>? FirstTransitions,
    [property: JsonPropertyName("lastTransitions")] IReadOnlyList<int>? LastTransitions,
    // op: "halfBit"
    [property: JsonPropertyName("halfBitSamples")] string? HalfBitSamples,
    // op: "framesPerSecond"
    [property: JsonPropertyName("framesPerSecond")] int? FramesPerSecond,
    // op: "bits"
    [property: JsonPropertyName("bitCount")] int? BitCount,
    [property: JsonPropertyName("firstBits")] string? FirstBits,
    [property: JsonPropertyName("lastBits")] string? LastBits);

/// <summary>
/// Builds the signal a case describes. A line-for-line mirror of
/// <c>LTCDecodeGolden.samples(for:)</c> — if the two ever disagree, every case
/// fails on <c>sampleCount</c> first, which is why that field is carried on every
/// op.
/// </summary>
internal static class LtcDecodeRecipe
{
    /// <summary>
    /// <b>The order is the contract:</b>
    /// <list type="number">
    /// <item>Encode <c>frameCount</c> consecutive frames from <c>timecode</c>,
    /// biphase polarity threaded across the joins exactly as
    /// <see cref="LtcFrameStream"/> does. Every frame named by <c>flips</c> is
    /// re-encoded from its word with that entry's <c>indices</c> toggled — so
    /// corruption is a genuinely wrong word on the wire, and the polarity thread
    /// carries its consequences into the frames that follow.</item>
    /// <item>Prepend <c>leadSilenceSamples</c> zeros, append
    /// <c>trailSilenceSamples</c> zeros.</item>
    /// <item>Truncate to <c>truncateToSamples</c> (a prefix).</item>
    /// <item>Add <c>offsetBy</c> to every sample.</item>
    /// </list>
    /// Silence is digital zero, not <c>±0</c> of some small amplitude, so the RMS
    /// arithmetic is unambiguous.
    /// </summary>
    public static float[] Samples(LtcDecodeInput input)
    {
        var output = new List<float>(new float[input.LeadSilenceSamples]);
        output.AddRange(Body(input));
        output.AddRange(new float[input.TrailSilenceSamples]);

        var samples = output.ToArray();
        if (input.TruncateToSamples is { } limit)
        {
            samples = samples.Take(Math.Max(0, limit)).ToArray();
        }

        if (input.OffsetBy is { } text)
        {
            var offset = (float)GoldenDouble.Parse(text);
            for (var index = 0; index < samples.Length; index++)
            {
                samples[index] += offset;
            }
        }

        return samples;
    }

    public static SmpteFramerate RateOf(LtcDecodeInput input) =>
        SmpteFramerateExtensions.FromRawValue(input.Rate);

    public static double SampleRateOf(LtcDecodeInput input) => GoldenDouble.Parse(input.SampleRate);

    public static float AmplitudeOf(LtcDecodeInput input) => (float)GoldenDouble.Parse(input.Amplitude);

    public static Timecode StartOf(LtcDecodeInput input)
    {
        var rate = RateOf(input);
        var components = input.Timecode;
        return Timecode.Create(components[0], components[1], components[2], components[3], rate)
               ?? throw new InvalidDataException(
                   $"[{string.Join(", ", components)}] is not a valid timecode at {input.Rate}");
    }

    private static float[] Body(LtcDecodeInput input)
    {
        if (input.FrameCount <= 0)
        {
            return [];
        }

        var start = StartOf(input);
        var framesPerSecond = RateOf(input).FramesPerSecond();
        var sampleRate = SampleRateOf(input);
        var amplitude = AmplitudeOf(input);

        var output = new List<float>();
        var level = false;
        for (var offset = 0; offset < input.FrameCount; offset++)
        {
            var (frameSamples, endLevel) = LtcEncoder.Samples(
                FrameAt(input, offset, start),
                framesPerSecond,
                sampleRate,
                amplitude,
                level);
            output.AddRange(frameSamples);
            level = endLevel;
        }

        return output.ToArray();
    }

    private static LtcFrame FrameAt(LtcDecodeInput input, int offset, Timecode start)
    {
        var rate = RateOf(input);
        var frame = LtcFrame.FromTimecode(Timecode.FromFrameCount(start.FrameCount + offset, rate));
        var indices = (input.Flips ?? [])
            .Where(flip => flip.Frame == offset)
            .SelectMany(flip => flip.Indices)
            .ToArray();
        if (indices.Length == 0)
        {
            return frame;
        }

        var bits = frame.Bits.ToArray();
        foreach (var index in indices)
        {
            bits[index] = !bits[index];
        }

        return LtcFrame.FromBits(bits);
    }
}
