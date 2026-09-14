using System.Text.Json.Serialization;

namespace OnlyCue.Core.Document;

/// <summary>End-of-media transport policy. <c>PlayOnce</c> preserves pre-v15
/// behaviour and is the absent-key default.</summary>
public enum PlaybackMode
{
    PlayOnce,
    Loop,
    AutoNext
}

/// <summary>
/// The root of a <c>.cuelist</c> document. Mirrors Swift <c>ProjectModel</c>
/// (<c>OnlyCue/Document/ProjectModel.swift</c>).
/// </summary>
/// <remarks>
/// A re-implementation, not shared code — the two sides are kept in lockstep by
/// <c>golden/cuelist-migration-v1.json</c> (epic #728, M1a). macOS is the source
/// of truth: change the Swift model first, regenerate the vector there, then
/// follow here.
/// </remarks>
public sealed class ProjectModel
{
    public const int CurrentSchemaVersion = 23;

    public int SchemaVersion { get; set; } = CurrentSchemaVersion;

    public Guid Id { get; set; }

    public string Name { get; set; } = string.Empty;

    public List<CuePointType> CuePointTypes { get; set; } = [];

    public List<MediaItem> Items { get; set; } = [];

    [JsonPropertyName("activeItemID")]
    public Guid? ActiveItemId { get; set; }

    public ProjectTimecodeSettings TimecodeSettings { get; set; } = ProjectTimecodeSettings.Default();

    public PlaybackMode PlaybackMode { get; set; } = PlaybackMode.PlayOnce;

    /// <summary>The name a fresh document's first cue type carries.</summary>
    public const string DefaultCuePointTypeName = "General";

    public const string DefaultCuePointTypeColorHex = "#4ECDC4";

    [JsonIgnore]
    public Guid? DefaultCuePointTypeId => CuePointTypes.Count > 0 ? CuePointTypes[0].Id : null;

    [JsonIgnore]
    public MediaItem? ActiveItem =>
        ActiveItemId is { } id ? Items.FirstOrDefault(item => item.Id == id) : null;

    public static CuePointType MakeDefaultCuePointType() => new()
    {
        Id = Guid.NewGuid(),
        Name = DefaultCuePointTypeName,
        ColorHex = DefaultCuePointTypeColorHex
    };

    /// <summary>Resolves a cue's display colour from its type; <c>null</c> when
    /// the <c>typeID</c> matches nothing.</summary>
    public string? ColorHexFor(Cue cue) =>
        CuePointTypes.FirstOrDefault(type => type.Id == cue.TypeId)?.ColorHex;

    /// <summary>Counts every cue across every item referencing the given type.</summary>
    public int CueCountFor(Guid typeId) =>
        Items.Sum(item => item.Cues.Count(cue => cue.TypeId == typeId));
}

/// <summary>
/// The project's timecode configuration (schema v10 onward): only the SMPTE
/// framerate lives here, each clip carrying its own
/// <c>StartTimecodeFrames</c>. Mirrors Swift <c>ProjectTimecodeSettings</c>.
/// </summary>
public sealed class ProjectTimecodeSettings
{
    public SmpteFramerate Framerate { get; set; } = SmpteFramerate.Fps30;

    public static ProjectTimecodeSettings Default() => new();

    /// <summary>The timecode at a playback position inside
    /// <paramref name="item"/>, rounded to the nearest frame. Negative
    /// <paramref name="seconds"/> clamp to the item's start TC.</summary>
    public Timecode TimecodeAt(double seconds, MediaItem item)
    {
        var playbackFrames = (int)Math.Round(
            seconds * Framerate.FramesPerSecond(), MidpointRounding.AwayFromZero);
        return Timecode.FromFrameCount(item.StartTimecodeFrames + Math.Max(0, playbackFrames), Framerate);
    }
}
