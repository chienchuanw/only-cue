namespace OnlyCue.Core.Midi;

/// <summary>
/// The timing plan for the MTC generator: maps host-clock time to the
/// quarter-frame bytes due at that time.
/// </summary>
/// <remarks>
/// <para>
/// Mirrors the Swift <c>MTCSchedule</c> (<c>OnlyCue/MIDI/MTCSchedule.swift</c>);
/// macOS is the source of truth and <c>golden/mtc-schedule-v1.json</c> is the
/// contract. The Swift type's <c>hostTicksPerSecond()</c> reads
/// <c>mach_timebase_info</c> and has no mirror — a Windows backend supplies
/// <see cref="TicksPerSecond"/> from <c>QueryPerformanceFrequency</c> instead,
/// which is why the value is injected on both sides.
/// </para>
/// <para>
/// Free-running: timecode advances from an anchor at the nominal rate rather than
/// chasing the player's clock, so it cannot wobble and cannot disagree with the
/// LTC engine, which free-runs from the identical <c>Timecode</c>. A seek builds
/// a fresh schedule rather than nudging this one.
/// </para>
/// <para>
/// <b>The two-frame convention.</b> Eight quarter-frames carry one complete value
/// and span two frames, so a receiver assembles a value two frames after the
/// sequence begins. v1 transmits the value uncompensated — the sequence beginning
/// at frame <c>N</c> carries <c>N</c>.
/// </para>
/// </remarks>
public sealed class MtcSchedule
{
    /// <summary>The tolerance in <see cref="QuarterFrameIndexAtOrAfter"/>, as a
    /// reciprocal: one part in a million of a quarter-frame.</summary>
    private const double IndexQuantum = 1_000_000;

    public MtcSchedule(Timecode startTimecode, ulong anchorHostTime, double ticksPerSecond)
    {
        if (!(ticksPerSecond > 0))
        {
            throw new ArgumentOutOfRangeException(
                nameof(ticksPerSecond), ticksPerSecond, "host clock must advance");
        }

        StartTimecode = startTimecode;
        AnchorHostTime = anchorHostTime;
        TicksPerSecond = ticksPerSecond;
    }

    /// <summary>One scheduled quarter-frame: the data byte and the host time it
    /// is due.</summary>
    public readonly record struct Message(byte Byte, ulong Timestamp);

    /// <summary>Timecode carried by the first quarter-frame sequence.</summary>
    public Timecode StartTimecode { get; }

    /// <summary>Host-clock time at which quarter-frame 0 is due.</summary>
    public ulong AnchorHostTime { get; }

    /// <summary>Host-clock ticks per wall-clock second.</summary>
    public double TicksPerSecond { get; }

    /// <summary>Host-clock ticks between consecutive quarter-frames — a quarter of
    /// a frame period, so 4 × the framerate messages per second.</summary>
    public double TicksPerQuarterFrame => TicksPerSecond / (StartTimecode.Rate.FramesPerSecond() * 4);

    /// <summary>Timecode carried by quarter-frame sequence <paramref name="index"/>
    /// (each sequence is eight messages and advances the value by two frames).</summary>
    public Timecode TimecodeForSequence(int index) =>
        Timecode.FromFrameCount(
            StartTimecode.FrameCount + (Math.Max(0, index) * MtcFrame.FramesPerSequence),
            StartTimecode.Rate);

    /// <summary>Host time at which quarter-frame <paramref name="index"/> is due.</summary>
    /// <remarks>Swift adds with the wrapping <c>&amp;+</c>; <c>unchecked</c> is
    /// explicit here so the behaviour does not depend on the project's
    /// overflow-checking setting. The rounding is half away from zero, matching
    /// Swift's <c>.rounded()</c> — at a coarse clock every odd index is a
    /// midpoint tie, and banker's rounding would place it a tick early.</remarks>
    public ulong TimestampForQuarterFrame(int index) =>
        unchecked(AnchorHostTime + (ulong)Math.Round(
            Math.Max(0, index) * TicksPerQuarterFrame, MidpointRounding.AwayFromZero));

    /// <summary>The data byte for quarter-frame <paramref name="index"/>.</summary>
    public byte ByteForQuarterFrame(int index)
    {
        var position = Math.Max(0, index);
        return MtcFrame.QuarterFrameByte(
            position % MtcFrame.PiecesPerTimecode,
            TimecodeForSequence(position / MtcFrame.PiecesPerTimecode));
    }

    /// <summary>
    /// Every quarter-frame due in the <b>half-open</b> window
    /// <c>[from, until)</c>.
    /// </summary>
    /// <remarks>Half-open is what lets the refill timer tile the timeline:
    /// passing the previous call's <c>until</c> as the next call's <c>from</c>
    /// yields each message exactly once, with no duplicate at the seam and no gap
    /// across it. A window opening before the anchor clamps to quarter-frame 0;
    /// an empty or inverted window yields nothing.</remarks>
    public Message[] Batch(ulong from, ulong until)
    {
        if (until <= from)
        {
            return [];
        }

        var first = Math.Max(0, QuarterFrameIndexAtOrAfter(from));
        var limit = Math.Max(0, QuarterFrameIndexAtOrAfter(until));
        if (limit <= first)
        {
            return [];
        }

        var messages = new Message[limit - first];
        for (var index = first; index < limit; index++)
        {
            messages[index - first] = new Message(ByteForQuarterFrame(index), TimestampForQuarterFrame(index));
        }

        return messages;
    }

    /// <summary>The lowest quarter-frame index whose timestamp is
    /// <c>&gt;= time</c>.</summary>
    /// <remarks>
    /// <para>
    /// Rounded before the ceiling so a timestamp this type itself produced (which
    /// was rounded on the way out) maps back to its own index rather than to the
    /// next one — otherwise tiled windows would drop a message at every seam.
    /// </para>
    /// <para>
    /// <b>This quantise is load-bearing, not defensive padding.</b> Over the
    /// first 200 messages at <c>ticksPerSecond = 1e9</c>, dropping it loses
    /// 74 of them at 24 fps and 66 at 30 fps; at 25 fps the quarter-frame period
    /// is exactly 10 000 000 ticks and nothing is lost, which is why the contract
    /// carries chains at all three. <see cref="Math.Ceiling(double)"/> is
    /// required for Swift's <c>.rounded(.up)</c> — a plain <c>Math.Round</c>
    /// there reintroduces the loss, and the golden vectors catch it.
    /// </para>
    /// <para>
    /// The inner <see cref="MidpointRounding.AwayFromZero"/> mirrors Swift's
    /// <c>.rounded()</c> faithfully but is <b>not</b> observable: banker's
    /// rounding would differ only where <c>exact × IndexQuantum</c> lands on an
    /// exact midpoint, and enumerating every clock × rate pair in the contract
    /// over the first 200 000 quarter-frames — each emitted timestamp and one
    /// tick either side, 7.2 M values — finds no such tie. No vector can pin it;
    /// it stays because mirroring the source of truth costs nothing.
    /// </para>
    /// </remarks>
    private int QuarterFrameIndexAtOrAfter(ulong time)
    {
        var offset = (double)time - AnchorHostTime;
        if (!(offset > 0))
        {
            return 0;
        }

        var exact = offset / TicksPerQuarterFrame;
        var rounded = Math.Round(exact * IndexQuantum, MidpointRounding.AwayFromZero) / IndexQuantum;
        return (int)Math.Ceiling(rounded);
    }
}
