using System.Globalization;

namespace OnlyCue.Core;

/// <summary>
/// An SMPTE timecode <c>HH:MM:SS:FF</c> (<c>;</c> between SS and FF for
/// drop-frame) at a given <see cref="SmpteFramerate"/>.
/// </summary>
/// <remarks>
/// A line-for-line re-implementation of the Swift <c>Timecode</c>
/// (<c>OnlyCue/LTC/Timecode.swift</c>) — the two are kept in lockstep by the
/// golden-vector contract (<c>golden/timecode-v1.json</c>, epic #728 M0), not by
/// shared code. Change one only together with the other, and regenerate the
/// vectors from the macOS side.
///
/// Stores the displayed components and the rate; <see cref="FrameCount"/> and
/// <see cref="TotalSeconds"/> are derived. For drop-frame the components↔count
/// mapping follows the standard rule — frame numbers <c>00</c> and <c>01</c> are
/// skipped at the top of every minute except every tenth minute — so
/// <see cref="FrameCount"/> is the <i>actual</i> number of frames elapsed since
/// <c>00:00:00:00</c>; the components are labels.
/// </remarks>
public readonly record struct Timecode
{
    /// <summary>Separators accepted by <see cref="Parse"/>. Mirrors the Swift
    /// <c>CharacterSet(charactersIn: ":;,. \t")</c>.</summary>
    private static readonly char[] FieldSeparators = [':', ';', ',', '.', ' ', '\t'];

    private Timecode(SmpteFramerate rate, int hours, int minutes, int seconds, int frames)
    {
        Rate = rate;
        Hours = hours;
        Minutes = minutes;
        Seconds = seconds;
        Frames = frames;
    }

    public SmpteFramerate Rate { get; }
    public int Hours { get; }
    public int Minutes { get; }
    public int Seconds { get; }
    public int Frames { get; }

    /// <summary>
    /// Builds from displayed components, or returns <c>null</c> if any component
    /// is out of range for <paramref name="rate"/> — or, for drop-frame, if the
    /// components name a frame number the counting rule skips
    /// (<c>00:MM:00;00</c> / <c>00:MM:00;01</c> for a non-tenth minute).
    /// </summary>
    public static Timecode? Create(int hours, int minutes, int seconds, int frames, SmpteFramerate rate)
    {
        if (hours is < 0 or >= 24 || minutes is < 0 or >= 60 || seconds is < 0 or >= 60)
        {
            return null;
        }

        if (frames < 0 || frames >= rate.FramesPerSecond())
        {
            return null;
        }

        if (rate.IsDropFrame() && seconds == 0 && frames < 2 && minutes % 10 != 0)
        {
            return null;
        }

        return new Timecode(rate, hours, minutes, seconds, frames);
    }

    /// <summary>
    /// Builds from a count of frames elapsed since <c>00:00:00:00</c>. A negative
    /// count clamps to zero; a count past <c>24:00:00:00</c> wraps modulo one day.
    /// </summary>
    public static Timecode FromFrameCount(int frameCount, SmpteFramerate rate)
    {
        var count = Math.Max(0, frameCount) % FramesPerDay(rate);
        if (rate.IsDropFrame())
        {
            // Standard reverse drop-frame conversion (30 fps base).
            const int framesPer10Min = 17982;  // 10 * 60 * 30 − 18
            const int framesPerMin = 1798;     // 60 * 30 − 2
            var tens = count / framesPer10Min;
            var within = count % framesPer10Min;
            count += 18 * tens;
            if (within >= 2)
            {
                count += 2 * ((within - 2) / framesPerMin);
            }
        }

        var fps = rate.FramesPerSecond();
        return new Timecode(
            rate,
            hours: count / fps / 60 / 60 % 24,
            minutes: count / fps / 60 % 60,
            seconds: count / fps % 60,
            frames: count % fps);
    }

    /// <summary>Builds from a wall-clock offset, rounding to the nearest frame.</summary>
    public static Timecode FromTotalSeconds(double totalSeconds, SmpteFramerate rate)
    {
        // Swift's `rounded()` is round-half-away-from-zero; C#'s default
        // `Math.Round` is banker's rounding, which would diverge on exact
        // midpoints (e.g. 1.5 s at 25 fps).
        var frames = Math.Max(0, Math.Round(totalSeconds * rate.FramesPerSecond(), MidpointRounding.AwayFromZero));
        return FromFrameCount((int)frames, rate);
    }

    /// <summary>
    /// Parses a <c>HH:MM:SS:FF</c> (or <c>HH:MM:SS;FF</c>) string for
    /// <paramref name="rate"/>. Any of <c>:</c>/<c>;</c>/<c>.</c>/<c>,</c> and
    /// whitespace separate the four fields. Returns <c>null</c> unless it is
    /// exactly four integer fields whose values are in range for the rate (and,
    /// for drop-frame, not a frame number the counting rule skips). The
    /// <c>;</c>-vs-<c>:</c> separator is punctuation only — drop-frame-ness comes
    /// from <paramref name="rate"/>.
    /// </summary>
    public static Timecode? Parse(string text, SmpteFramerate rate)
    {
        var fields = text.Split(FieldSeparators, StringSplitOptions.RemoveEmptyEntries);
        if (fields.Length != 4)
        {
            return null;
        }

        Span<int> values = stackalloc int[4];
        for (var i = 0; i < 4; i++)
        {
            if (!int.TryParse(fields[i], NumberStyles.Integer, CultureInfo.InvariantCulture, out values[i]))
            {
                return null;
            }
        }

        return Create(values[0], values[1], values[2], values[3], rate);
    }

    /// <summary>Frames elapsed since <c>00:00:00:00</c> (drop-frame aware).</summary>
    public int FrameCount
    {
        get
        {
            var fps = Rate.FramesPerSecond();
            var basis = (((Hours * 60) + Minutes) * 60 + Seconds) * fps + Frames;
            if (!Rate.IsDropFrame())
            {
                return basis;
            }

            var totalMinutes = (Hours * 60) + Minutes;
            return basis - 2 * (totalMinutes - totalMinutes / 10);
        }
    }

    /// <summary>
    /// Wall-clock seconds since <c>00:00:00:00</c>. Nominal — drop-frame divides
    /// by 30.0, not 29.97 (the v1 simplification the Swift side also makes).
    /// </summary>
    public double TotalSeconds => (double)FrameCount / Rate.FramesPerSecond();

    public string DisplayString
    {
        get
        {
            var separator = Rate.IsDropFrame() ? ';' : ':';
            return string.Create(
                CultureInfo.InvariantCulture,
                $"{Hours:D2}:{Minutes:D2}:{Seconds:D2}{separator}{Frames:D2}");
        }
    }

    public override string ToString() => DisplayString;

    private static int FramesPerDay(SmpteFramerate rate)
    {
        var nonDrop = 24 * 60 * 60 * rate.FramesPerSecond();
        if (!rate.IsDropFrame())
        {
            return nonDrop;
        }

        const int minutesPerDay = 24 * 60;
        return nonDrop - 2 * (minutesPerDay - minutesPerDay / 10);
    }
}
