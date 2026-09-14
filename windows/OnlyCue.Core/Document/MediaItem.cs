using System.Text.Json.Serialization;

namespace OnlyCue.Core.Document;

public enum MediaKind
{
    Audio,
    Video
}

/// <summary>
/// Where a clip's media lives. Mirrors Swift <c>MediaReference</c>. The Windows
/// port has no security-scoped bookmarks, but <see cref="BookmarkData"/> is
/// carried verbatim so a document round-trips through either platform
/// unchanged (ADR-006).
/// </summary>
public sealed class MediaReference
{
    public string DisplayName { get; set; } = string.Empty;

    public MediaKind Kind { get; set; }

    public double Duration { get; set; }

    public byte[] BookmarkData { get; set; } = [];

    /// <summary>Path relative to the <c>.cuelist</c> inside an exported bundle
    /// (#640); absent in a normal working document. Schema v16.</summary>
    public string? BundlePath { get; set; }
}

/// <summary>Which channel of a media file carries LTC, as the user declared it
/// (#793). Mirrors Swift <c>LTCChannelSelection</c>.</summary>
public enum LtcChannelKind
{
    /// <summary>Scan every channel and take the first that corroborates.</summary>
    Auto,

    /// <summary>The user named a zero-based channel index.</summary>
    Channel,

    /// <summary>The user asserts this file carries no LTC.</summary>
    None
}

/// <summary>
/// Mirrors Swift <c>LTCChannelSelection</c>, including its flat string encoding
/// (<c>"auto"</c> / <c>"none"</c> / <c>"channel:2"</c>). <c>default</c> is
/// <see cref="LtcChannelKind.Auto"/>, which is also the absent-key default.
/// </summary>
public readonly record struct LtcChannelSelection(LtcChannelKind Kind, int Index)
{
    private const string ChannelPrefix = "channel:";

    public static LtcChannelSelection Auto => default;

    public static LtcChannelSelection Denied => new(LtcChannelKind.None, 0);

    public static LtcChannelSelection Channel(int index) => new(LtcChannelKind.Channel, index);

    public bool IsAuto => Kind == LtcChannelKind.Auto;

    /// <summary>Whether the user has asserted this file carries no LTC, so
    /// neither the scan nor a remembered track may surface a readout.</summary>
    public bool DeniesLtc => Kind == LtcChannelKind.None;

    public string RawValue => Kind switch
    {
        LtcChannelKind.None => "none",
        LtcChannelKind.Channel => ChannelPrefix + Index.ToString(System.Globalization.CultureInfo.InvariantCulture),
        _ => "auto"
    };

    /// <summary>
    /// Parses the persisted form. An unparseable or negative index falls back to
    /// <see cref="Auto"/> rather than failing the load — the same promise Swift
    /// makes, and with the same limit: a value of the wrong <i>type</i> is a
    /// different problem from a typo in this one and is left to the deserialiser.
    /// </summary>
    public static LtcChannelSelection Parse(string? raw)
    {
        if (raw == "none")
        {
            return Denied;
        }

        if (raw is null || !raw.StartsWith(ChannelPrefix, StringComparison.Ordinal))
        {
            return Auto;
        }

        var suffix = raw[ChannelPrefix.Length..];
        return int.TryParse(suffix, System.Globalization.NumberStyles.Integer,
            System.Globalization.CultureInfo.InvariantCulture, out var index) && index >= 0
            ? Channel(index)
            : Auto;
    }
}

/// <summary>
/// One clip and everything authored against it. Mirrors Swift <c>MediaItem</c>.
/// </summary>
public sealed class MediaItem
{
    public Guid Id { get; set; }

    public MediaReference Media { get; set; } = new();

    public List<Cue> Cues { get; set; } = [];

    /// <summary>Frames since <c>00:00:00:00</c> at the project framerate.
    /// Replaced the project-wide <c>startOffsetFrames</c> in v10.</summary>
    public int StartTimecodeFrames { get; set; }

    public bool LtcMuted { get; set; }

    /// <summary>Per-clip display override; falls back to
    /// <c>Media.DisplayName</c>. Schema v12.</summary>
    public string? AlternateName { get; set; }

    public Lyrics Lyrics { get; set; } = Lyrics.Empty();

    /// <summary>Last grandMA2 push destination (#683). Schema v17.</summary>
    [JsonPropertyName("ma2PushTarget")]
    public Ma2PushTarget? Ma2PushTarget { get; set; }

    /// <summary>When false (the default, "music-only") the LTC tone channel is
    /// muted during playback. Schema v19.</summary>
    public bool PlaysOriginalSourceAudio { get; set; }

    /// <summary>The song's remembered LTC (#754). Schema v20.</summary>
    [JsonPropertyName("rememberedLTC")]
    public StripedTimecodeTrack? RememberedLtc { get; set; }

    /// <summary>User-assigned colour tag, <c>"#RRGGBB"</c>; <c>null</c> means
    /// untagged. Schema v22.</summary>
    public string? ColorHex { get; set; }

    /// <summary>Schema v23 (#793).</summary>
    [JsonIgnore]
    public LtcChannelSelection LtcChannelSelection { get; set; }

    /// <summary>
    /// The persisted face of <see cref="LtcChannelSelection"/>. Written only when
    /// the user has actually chosen: encoding <c>auto</c> would add a key saying
    /// "default" to every item in every document, and
    /// <see cref="CuelistJson"/> drops nulls.
    /// </summary>
    [JsonInclude]
    [JsonPropertyName("ltcChannelSelection")]
    public string? LtcChannelSelectionRaw
    {
        get => LtcChannelSelection.IsAuto ? null : LtcChannelSelection.RawValue;
        set => LtcChannelSelection = LtcChannelSelection.Parse(value);
    }

    /// <summary>User-facing name for this clip: the trimmed
    /// <see cref="AlternateName"/> when non-empty, else the file basename.</summary>
    [JsonIgnore]
    public string ResolvedName =>
        string.IsNullOrWhiteSpace(AlternateName) ? Media.DisplayName : AlternateName.Trim();
}
