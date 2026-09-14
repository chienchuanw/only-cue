using OnlyCue.Core.Document;

namespace OnlyCue.Core.Tempo;

/// <summary>A beat on the grid, and whether it opens a bar.</summary>
public readonly record struct Beat(double Time, bool IsDownbeat);

/// <summary>
/// The beat/bar grid rendered on the waveform and used as a snap target. Derived
/// at read time from the item's cues: each cue with a non-null <c>Bpm</c> opens a
/// constant-tempo segment running until the next BPM-bearing cue (or
/// <c>itemDuration</c>). The cue's own time is bar 1, beat 1 — no separate
/// downbeat offset. <c>BeatsPerBar</c> is inherited from the previous segment when
/// the cue leaves it null; defaulted to 4 if no upstream meter exists.
/// </summary>
/// <remarks>
/// A line-for-line re-implementation of the Swift <c>DerivedTempoGrid</c>
/// (<c>OnlyCue/Tempo/DerivedTempoGrid.swift</c>), kept in lockstep by the
/// golden-vector contract (<c>golden/tempo-grid-v1.json</c>, epic #728 M1b).
///
/// Three translation hazards, all pinned by the vector:
/// <list type="bullet">
/// <item>Swift's <c>.rounded()</c> is round-half-<b>away-from-zero</b>; .NET's
/// parameterless <c>Math.Round</c> is banker's rounding, which resolves a point
/// query landing exactly between two beats to the other side.</item>
/// <item><c>.rounded(.up)</c>/<c>.rounded(.down)</c> are ceiling/floor, <b>not</b>
/// truncation. A C# <c>(int)</c> cast truncates toward zero and diverges for a
/// range starting before the segment anchor.</item>
/// <item>Beat times are recomputed as <c>anchor + index * step</c>, never
/// accumulated — an accumulated sum drifts in the low bits and fails the
/// contract's bitwise comparison.</item>
/// </list>
/// </remarks>
public sealed class DerivedTempoGrid
{
    private const int DefaultBeatsPerBar = 4;
    private const double Epsilon = 1e-9;

    public sealed record Segment(double StartSeconds, double Bpm, int BeatsPerBar)
    {
        public double BeatDuration => 60.0 / Bpm;

        public double BarDuration => BeatDuration * BeatsPerBar;
    }

    public IReadOnlyList<Segment> Segments { get; }

    public bool IsEmpty => Segments.Count == 0;

    private DerivedTempoGrid(IReadOnlyList<Segment> segments) => Segments = segments;

    public static DerivedTempoGrid From(IEnumerable<Cue> cues)
    {
        // OrderBy is a stable sort, which is what Swift's `sorted(by:)` does in
        // practice — and the co-located-cue case below depends on the relative
        // order of equal-time cues, so the vector pins it rather than leaving it
        // to chance.
        var bpmCues = cues.Where(cue => cue.Bpm.HasValue).OrderBy(cue => cue.Time).ToList();
        if (bpmCues.Count == 0)
        {
            return new DerivedTempoGrid([]);
        }

        var built = new List<Segment>();
        foreach (var cue in bpmCues)
        {
            if (cue.Bpm is not { } bpm)
            {
                continue;
            }

            var meter = cue.BeatsPerBar
                ?? (built.Count > 0 ? built[^1].BeatsPerBar : DefaultBeatsPerBar);
            var clampedBpm = Math.Min(Math.Max(bpm, 20), 400);
            var clampedMeter = Math.Max(1, Math.Min(meter, 16));
            var startSeconds = Math.Max(0, cue.Time);

            // De-dup co-located BPM cues: the last one wins (matches the user's
            // mental model of "most recent edit takes effect"). Without this, a
            // zero-width earlier segment would contribute no beats and the earlier
            // cue's tempo would silently disappear.
            if (built.Count > 0 && Math.Abs(built[^1].StartSeconds - startSeconds) < Epsilon)
            {
                built[^1] = new Segment(startSeconds, clampedBpm, clampedMeter);
            }
            else
            {
                built.Add(new Segment(startSeconds, clampedBpm, clampedMeter));
            }
        }

        return new DerivedTempoGrid(built);
    }

    private double SegmentEndSeconds(int index, double itemDuration) =>
        index + 1 < Segments.Count ? Segments[index + 1].StartSeconds : itemDuration;

    public IReadOnlyList<Beat> BeatTimes(double lowerBound, double upperBound, double itemDuration)
    {
        if (Segments.Count == 0)
        {
            return [];
        }

        var output = new List<Beat>();
        for (var index = 0; index < Segments.Count; index++)
        {
            var spanEnd = SegmentEndSeconds(index, itemDuration);
            var isLast = index + 1 == Segments.Count;
            output.AddRange(Beats(Segments[index], spanEnd, isLast, lowerBound, upperBound));
        }

        return output;
    }

    public IReadOnlyList<double> BarTimes(double lowerBound, double upperBound, double itemDuration) =>
        BeatTimes(lowerBound, upperBound, itemDuration)
            .Where(beat => beat.IsDownbeat)
            .Select(beat => beat.Time)
            .ToList();

    public double? NearestBeat(double seconds, double itemDuration) =>
        NearestGridLine(seconds, itemDuration, segment => segment.BeatDuration);

    public double? NearestBar(double seconds, double itemDuration) =>
        NearestGridLine(seconds, itemDuration, segment => segment.BarDuration);

    // MARK: - Internals

    private static IEnumerable<Beat> Beats(
        Segment segment,
        double spanEnd,
        bool isLast,
        double rangeLowerBound,
        double rangeUpperBound)
    {
        var lower = Math.Max(rangeLowerBound, segment.StartSeconds);
        var upper = Math.Min(rangeUpperBound, spanEnd);
        if (upper < lower - Epsilon)
        {
            yield break;
        }

        var step = segment.BeatDuration;
        var anchor = segment.StartSeconds;
        var firstIndex = (int)Math.Ceiling((lower - anchor) / step);
        // Segment span is half-open EXCEPT for the last segment, which closes at
        // itemDuration — a beat landing exactly on itemDuration is included.
        var spanCeiling = isLast ? spanEnd : spanEnd - Epsilon;
        var lastIndexInSpan = (int)Math.Floor((spanCeiling - anchor) / step);
        var lastIndexInRange = (int)Math.Floor((upper - anchor) / step);
        var lastIndex = Math.Min(lastIndexInSpan, lastIndexInRange);

        for (var beatIndex = firstIndex; beatIndex <= lastIndex; beatIndex++)
        {
            var time = anchor + (beatIndex * step);
            if (time < segment.StartSeconds - Epsilon)
            {
                continue;
            }

            // Half-open at segment-to-segment boundaries: the boundary belongs to
            // the next segment. The segment's own first beat (beatIndex == 0) lives
            // here. At the item's trailing end (isLast), the boundary is closed.
            if (!isLast && beatIndex > 0 && time >= spanEnd - Epsilon)
            {
                continue;
            }

            var modulo = ((beatIndex % segment.BeatsPerBar) + segment.BeatsPerBar) % segment.BeatsPerBar;
            yield return new Beat(time, modulo == 0);
        }
    }

    private double? NearestGridLine(double seconds, double itemDuration, Func<Segment, double> stride)
    {
        if (Segments.Count == 0)
        {
            return null;
        }

        int? coveringIndex = null;
        for (var index = 0; index < Segments.Count; index++)
        {
            if (Segments[index].StartSeconds <= seconds + Epsilon)
            {
                coveringIndex = index;
            }
        }

        if (coveringIndex is not { } covering)
        {
            return null;
        }

        var segment = Segments[covering];
        var spanEnd = SegmentEndSeconds(covering, itemDuration);
        var step = stride(segment);
        if (step <= 0)
        {
            return segment.StartSeconds;
        }

        var anchor = segment.StartSeconds;
        var rounded = Math.Round((seconds - anchor) / step, MidpointRounding.AwayFromZero);
        var candidate = anchor + (rounded * step);
        if (candidate < segment.StartSeconds)
        {
            candidate = segment.StartSeconds;
        }

        if (candidate >= spanEnd - Epsilon)
        {
            var last = Math.Floor((spanEnd - Epsilon - anchor) / step);
            candidate = anchor + (last * step);
        }

        // Prefer the next segment's start (its first downbeat / beat boundary)
        // when it's closer than our in-segment candidate.
        if (covering + 1 < Segments.Count)
        {
            var next = Segments[covering + 1].StartSeconds;
            if (Math.Abs(next - seconds) < Math.Abs(candidate - seconds))
            {
                return next;
            }
        }

        return Math.Max(segment.StartSeconds, candidate);
    }
}
