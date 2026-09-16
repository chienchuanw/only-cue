namespace OnlyCue.Core.Ltc;

/// <summary>
/// The buffer plan for the LTC playback engine: maps a sequential buffer index to
/// the audio samples and the timecode that buffer carries.
/// </summary>
/// <remarks>
/// <para>
/// Mirrors the Swift <c>LTCSchedule</c> (<c>OnlyCue/LTC/LTCSchedule.swift</c>);
/// macOS is the source of truth and <c>golden/ltc-schedule-v1.json</c> is the
/// contract.
/// </para>
/// <para>
/// Each buffer is <see cref="FramesPerBuffer"/> whole LTC frames. Within a buffer
/// the biphase polarity is threaded (via <see cref="LtcFrameStream"/>); between
/// buffers it resets to the canonical start level. That is seamless — but not
/// for the reason one might assume. Each frame emits 80 bit-boundary flips plus
/// one mid-bit flip per <c>1</c> bit, and the parity bit forces an even number of
/// ones, so the flip count is even and the end level always equals the start
/// level. <b>The parity bit is what makes the buffer joins seamless</b>; a port
/// with the parity bit in the wrong place would glitch audibly at every boundary.
/// </para>
/// </remarks>
public sealed class LtcSchedule
{
    public LtcSchedule(
        Timecode startTimecode,
        double sampleRate,
        int framesPerBuffer,
        float amplitude = LtcEncoder.DefaultAmplitude)
    {
        if (!(sampleRate > 0))
        {
            throw new ArgumentOutOfRangeException(nameof(sampleRate), sampleRate, "sample rate must be positive");
        }

        if (framesPerBuffer < 1)
        {
            throw new ArgumentOutOfRangeException(
                nameof(framesPerBuffer), framesPerBuffer, "a buffer holds at least one LTC frame");
        }

        StartTimecode = startTimecode;
        SampleRate = sampleRate;
        FramesPerBuffer = framesPerBuffer;
        Amplitude = amplitude;
    }

    /// <summary>One scheduled buffer: its sequence index, the timecode of its
    /// first frame, and the audio samples.</summary>
    public readonly record struct Buffer(int Index, Timecode Timecode, float[] Samples);

    public Timecode StartTimecode { get; }
    public double SampleRate { get; }

    /// <summary>Whole LTC frames per scheduled audio buffer (≥ 1).</summary>
    public int FramesPerBuffer { get; }
    public float Amplitude { get; }

    /// <summary>Buffers handed out by <see cref="NextBuffer"/> so far.</summary>
    public int EmittedBuffers { get; private set; }

    private int FramesPerSecond => StartTimecode.Rate.FramesPerSecond();

    /// <summary>
    /// Audio samples in one scheduled buffer.
    /// </summary>
    /// <remarks>
    /// <b>Rounds per frame and then multiplies</b>, which is not the same as
    /// rounding the product: at 44 100 Hz / 24 fps this is
    /// <c>4 × round(1837.5) = 7352</c>, where <c>round(4 × 1837.5)</c> would give
    /// 7350 — two samples short per buffer, forever. The order is contract, and
    /// <c>golden/ltc-schedule-v1.json</c> pins it.
    /// </remarks>
    public int SamplesPerBuffer =>
        FramesPerBuffer * (int)Math.Round(SampleRate / FramesPerSecond, MidpointRounding.AwayFromZero);

    /// <summary>Wall-clock duration of one scheduled buffer.</summary>
    public double BufferDuration => (double)FramesPerBuffer / FramesPerSecond;

    /// <summary>Timecode at the start of buffer <paramref name="index"/> (0-based).</summary>
    public Timecode TimecodeForBufferIndex(int index) =>
        Timecode.FromFrameCount(StartTimecode.FrameCount + (Math.Max(0, index) * FramesPerBuffer), StartTimecode.Rate);

    /// <summary>Samples for buffer <paramref name="index"/> — a seamless
    /// <see cref="LtcFrameStream"/> run of <see cref="FramesPerBuffer"/> frames.</summary>
    public float[] SamplesForBufferIndex(int index) =>
        new LtcFrameStream(TimecodeForBufferIndex(index), SampleRate, Amplitude).Samples(FramesPerBuffer);

    /// <summary>Buffer <paramref name="index"/> as a <see cref="Buffer"/> value.</summary>
    public Buffer BufferAt(int index) =>
        new(index, TimecodeForBufferIndex(index), SamplesForBufferIndex(index));

    /// <summary>Hand out the next buffer in sequence (advances
    /// <see cref="EmittedBuffers"/>).</summary>
    public Buffer NextBuffer()
    {
        var result = BufferAt(EmittedBuffers);
        EmittedBuffers++;
        return result;
    }

    /// <summary>
    /// How many buffers should have been emitted to cover
    /// <paramref name="elapsedSeconds"/> of playback plus
    /// <paramref name="leadBuffers"/> of look-ahead headroom. A negative elapsed
    /// time clamps to 0.
    /// </summary>
    /// <remarks>Swift's <c>.rounded(.up)</c> is <see cref="Math.Ceiling(double)"/>,
    /// not <c>Math.Round</c>: a fifth of a buffer of playback still needs a whole
    /// buffer scheduled, and rounding instead would starve the engine.</remarks>
    public int TargetBufferCount(double elapsedSeconds, int leadBuffers)
    {
        var covering = (int)Math.Ceiling(Math.Max(0, elapsedSeconds) / BufferDuration);
        return covering + Math.Max(0, leadBuffers);
    }

    /// <summary>
    /// <see cref="FramesPerBuffer"/> for a buffer of about
    /// <paramref name="targetSeconds"/> at <paramref name="rate"/> (≥ 1).
    /// </summary>
    /// <remarks>Half away from zero, not banker's: 0.1 s at 25 fps is 2.5 frames,
    /// which is <b>3</b> here and would be 2 under the default
    /// <c>Math.Round(double)</c>.</remarks>
    public static int FramesPerBufferForTargetSeconds(double targetSeconds, SmpteFramerate rate) =>
        Math.Max(
            1,
            (int)Math.Round(Math.Max(0, targetSeconds) * rate.FramesPerSecond(), MidpointRounding.AwayFromZero));
}
