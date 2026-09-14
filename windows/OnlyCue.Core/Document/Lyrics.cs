namespace OnlyCue.Core.Document;

/// <summary>
/// A single lyric line. <see cref="Time"/> is song-relative seconds;
/// <c>null</c> means the line is <i>unplaced</i> — it has text but no timestamp
/// yet. Mirrors Swift <c>LyricLine</c>.
/// </summary>
public sealed class LyricLine
{
    public Guid Id { get; set; }

    public double? Time { get; set; }

    public string Text { get; set; } = string.Empty;

    /// <summary>Clamps <see cref="Time"/> to <c>&gt;= 0</c>, as Swift's
    /// <c>LyricLine.init</c> does on every construction and decode.</summary>
    public LyricLine Clamped()
    {
        Time = Time is { } time ? Math.Max(0, time) : null;
        return this;
    }
}

/// <summary>
/// The lyrics attached to one <see cref="MediaItem"/> — a reference/HUD layer
/// decoupled from cues (ADR-022). Mirrors Swift <c>Lyrics</c>.
/// </summary>
/// <remarks>
/// Two clocks: <c>LyricLine.Time</c> is song-relative, <see cref="OffsetSeconds"/>
/// is the media playback time at which the song begins. <see cref="Lines"/> is
/// kept in authoring order, with placed and unplaced lines interleaved.
/// </remarks>
public sealed class Lyrics
{
    public List<LyricLine> Lines { get; set; } = [];

    public double OffsetSeconds { get; set; }

    public static Lyrics Empty() => new();
}
