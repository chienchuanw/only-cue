using System.Text.Json;
using System.Text.Json.Serialization;

namespace OnlyCue.Core.Document;

/// <summary>Raised when a document declares a schema version this build has no
/// rung for. Mirrors Swift <c>ProjectModel.LoadError.unsupportedSchemaVersion</c>.</summary>
public sealed class UnsupportedSchemaVersionException(int schemaVersion)
    : Exception($"unsupported .cuelist schema version {schemaVersion}")
{
    public int SchemaVersion { get; } = schemaVersion;
}

/// <summary>
/// Reads a <c>.cuelist</c> payload of any historical schema version and returns
/// the current model — the C# half of the migration ladder.
/// </summary>
/// <remarks>
/// A re-implementation of Swift's <c>ProjectModel.decode(from:)</c> and its
/// <c>migrateFromVN</c> family. Every rung lands the document directly on the
/// current schema rather than stepping one version at a time, exactly as the
/// Swift side does.
///
/// <para>One structural difference is worth naming: Swift's synthesised
/// <c>Decodable</c> <i>throws</i> on a missing required key, which is what makes
/// each <c>LegacyVN</c> snapshot struct a real assertion about that version's
/// on-disk shape. <see cref="JsonSerializer"/> instead leaves an absent property
/// at its default. So the legacy DTOs below document the shape rather than
/// enforce it, and this side is the more permissive of the two. The golden
/// vector pins the agreed behaviour for documents that <i>are</i> well-formed;
/// it says nothing about malformed ones, and neither does this class.</para>
/// </remarks>
public static class ProjectModelCodec
{
    public static ProjectModel Decode(string json)
    {
        var probe = JsonSerializer.Deserialize<VersionProbe>(json, CuelistJson.Options)
                    ?? throw new JsonException("document did not deserialise");

        return probe.SchemaVersion switch
        {
            1 => MigrateFromV1(Require<LegacyV1>(json)),
            2 => MigrateFromV2(Require<LegacyV2>(json)),
            3 => MigrateFromV3(Require<LegacyV3>(json)),
            4 => MigrateFromV4(Require<LegacyV4>(json)),
            5 => MigrateFromV5(Require<LegacyV5>(json)),
            6 => MigrateFromV6(Require<LegacyV6>(json)),
            7 => MigrateFromV7(Require<LegacyV7>(json)),
            8 or 9 => MigrateFromV8OrV9(Require<LegacyV8>(json)),
            10 => MigrateFromV10(Require<LegacyV10>(json)),

            // v11 → v23 are all additive: every field those versions gained is
            // absent-means-default, so the current shape decodes them as-is and
            // the only work is re-stamping the version. They are listed one per
            // line rather than collapsed into a range so that a future rung which
            // is *not* a pure re-stamp has an obvious place to break out of.
            11 => ReStamp(DecodeCurrentShape(json)),   // v12 added MediaItem.alternateName
            12 => ReStamp(DecodeCurrentShape(json)),   // v13 added MediaItem.lyrics
            13 => ReStamp(DecodeCurrentShape(json)),   // v14 made LyricLine.time optional
            14 => ReStamp(DecodeCurrentShape(json)),   // v15 added ProjectModel.playbackMode
            15 => ReStamp(DecodeCurrentShape(json)),   // v16 added MediaReference.bundlePath
            16 => ReStamp(DecodeCurrentShape(json)),   // v17 added MediaItem.ma2PushTarget
            17 => ReStamp(DecodeCurrentShape(json)),   // v18 added MA2PushTarget.sequenceName
            18 => ReStamp(DecodeCurrentShape(json)),   // v19 added playsOriginalSourceAudio
            19 => ReStamp(DecodeCurrentShape(json)),   // v20 added MediaItem.rememberedLTC
            20 => ReStamp(DecodeCurrentShape(json)),   // v21 made the MA2 executor optional
            21 => ReStamp(DecodeCurrentShape(json)),   // v22 added MediaItem.colorHex
            22 => ReStamp(DecodeCurrentShape(json)),   // v23 added ltcChannelSelection + validFrom/Until

            ProjectModel.CurrentSchemaVersion => DecodeCurrentShape(json),
            var other => throw new UnsupportedSchemaVersionException(other)
        };
    }

    public static string Encode(ProjectModel model) => JsonSerializer.Serialize(model, CuelistJson.Options);

    private static T Require<T>(string json) =>
        JsonSerializer.Deserialize<T>(json, CuelistJson.Options)
        ?? throw new JsonException($"document did not deserialise as {typeof(T).Name}");

    /// <summary>Decodes a document already shaped like the current schema and
    /// applies the normalisation Swift performs inside its decoding
    /// initialisers.</summary>
    private static ProjectModel DecodeCurrentShape(string json) => Normalised(Require<ProjectModel>(json));

    private static ProjectModel ReStamp(ProjectModel model)
    {
        model.SchemaVersion = ProjectModel.CurrentSchemaVersion;
        return model;
    }

    /// <summary>
    /// Swift clamps <c>bpm</c>/<c>beatsPerBar</c> and <c>LyricLine.time</c> inside
    /// the decoding initialisers themselves, so every load is normalised no
    /// matter which rung it came through. <see cref="JsonSerializer"/> assigns
    /// properties directly, so the same guarantee has to be re-applied here —
    /// once, over the whole graph, at the single point documents enter.
    /// </summary>
    private static ProjectModel Normalised(ProjectModel model)
    {
        foreach (var item in model.Items)
        {
            NormaliseItem(item);
        }

        return model;
    }

    private static MediaItem NormaliseItem(MediaItem item)
    {
        foreach (var cue in item.Cues)
        {
            cue.Clamped();
        }

        foreach (var line in item.Lyrics.Lines)
        {
            line.Clamped();
        }

        return item;
    }

    // MARK: - Cue numbering

    /// <summary>
    /// Sorts cues by time and assigns 1-based sequential numbers, for the v1–v3
    /// documents that predate <c>Cue.cueNumber</c>.
    /// </summary>
    /// <remarks>
    /// Equal times tie-break on the uppercase UUID string, matching Swift. There
    /// the rule is load-bearing because <c>Array.sorted(by:)</c> is not
    /// spec-stable; here <see cref="Enumerable.OrderBy{TSource,TKey}(IEnumerable{TSource},Func{TSource,TKey})"/>
    /// is stable and would preserve document order instead — which is a
    /// <i>different</i> answer from Swift's whenever two cues share a time. The
    /// explicit tie-break is what makes the two agree.
    /// </remarks>
    private static List<Cue> AssignCueNumbersBySort(IEnumerable<Cue> pending) =>
        pending
            .OrderBy(cue => cue.Time)
            .ThenBy(cue => cue.Id.ToString("D").ToUpperInvariant(), StringComparer.Ordinal)
            .Select((cue, index) =>
            {
                cue.CueNumber = index + 1;
                return cue;
            })
            .ToList();

    // MARK: - v1 … v5

    private static ProjectModel MigrateFromV1(LegacyV1 legacy)
    {
        var defaultType = ProjectModel.MakeDefaultCuePointType();
        var items = new List<MediaItem>();
        Guid? active = null;

        if (legacy.Media is { } media)
        {
            var item = new MediaItem
            {
                Id = Guid.NewGuid(),
                Media = media,
                Cues = AssignCueNumbersBySort(legacy.Cues.Select(cue => cue.ToCue(defaultType.Id)))
            };
            items.Add(item);
            active = item.Id;
        }

        return new ProjectModel
        {
            Id = legacy.Id,
            Name = legacy.Name,
            CuePointTypes = [defaultType],
            Items = items,
            ActiveItemId = active
        };
    }

    private static ProjectModel MigrateFromV2(LegacyV2 legacy)
    {
        var defaultType = ProjectModel.MakeDefaultCuePointType();
        return new ProjectModel
        {
            Id = legacy.Id,
            Name = legacy.Name,
            CuePointTypes = [defaultType],
            Items = legacy.Items.Select(item => new MediaItem
            {
                Id = item.Id,
                Media = item.Media,
                Cues = AssignCueNumbersBySort(item.Cues.Select(cue => cue.ToCue(defaultType.Id)))
            }).ToList(),
            ActiveItemId = legacy.ActiveItemId
        };
    }

    private static ProjectModel MigrateFromV3(LegacyV3 legacy) => new()
    {
        Id = legacy.Id,
        Name = legacy.Name,
        CuePointTypes = legacy.CuePointTypes,
        Items = legacy.Items.Select(item => new MediaItem
        {
            Id = item.Id,
            Media = item.Media,
            Cues = AssignCueNumbersBySort(item.Cues.Select(cue => cue.ToCue()))
        }).ToList(),
        ActiveItemId = legacy.ActiveItemId
    };

    private static ProjectModel MigrateFromV4(LegacyV4 legacy) => new()
    {
        Id = legacy.Id,
        Name = legacy.Name,
        CuePointTypes = legacy.CuePointTypes,
        Items = legacy.Items.Select(item => new MediaItem
        {
            Id = item.Id,
            Media = item.Media,
            Cues = item.Cues.Select(cue => cue.ToCue()).ToList()
        }).ToList(),
        ActiveItemId = legacy.ActiveItemId
    };

    private static ProjectModel MigrateFromV5(LegacyV5 legacy) => new()
    {
        Id = legacy.Id,
        Name = legacy.Name,
        CuePointTypes = legacy.CuePointTypes,
        Items = legacy.Items.Select(item => new MediaItem
        {
            Id = item.Id,
            Media = item.Media,
            Cues = item.Cues.Select(cue => cue.ToCue()).ToList()
        }).ToList(),
        ActiveItemId = legacy.ActiveItemId
    };

    // MARK: - v6, v7 (pre-tempoMap)

    /// <summary>v6 predates both <c>timecodeSettings</c> and <c>tempoMap</c>:
    /// seed the default timecode settings, leave every item at start TC 0.</summary>
    private static ProjectModel MigrateFromV6(LegacyV6 legacy) => new()
    {
        Id = legacy.Id,
        Name = legacy.Name,
        CuePointTypes = legacy.CuePointTypes,
        Items = legacy.Items.Select(item => item.ToMediaItem()).ToList(),
        ActiveItemId = legacy.ActiveItemId,
        TimecodeSettings = ProjectTimecodeSettings.Default()
    };

    /// <summary>v7 predates <c>tempoMap</c> and still carries the project-wide
    /// <c>startOffsetFrames</c> (dropped in v10), which fans onto each item.</summary>
    private static ProjectModel MigrateFromV7(LegacyV7 legacy) => new()
    {
        Id = legacy.Id,
        Name = legacy.Name,
        CuePointTypes = legacy.CuePointTypes,
        Items = legacy.Items
            .Select(item => item.ToMediaItem(legacy.TimecodeSettings.StartOffsetFrames))
            .ToList(),
        ActiveItemId = legacy.ActiveItemId,
        TimecodeSettings = new ProjectTimecodeSettings { Framerate = legacy.TimecodeSettings.Framerate }
    };

    // MARK: - v8 … v10 (tempoMap fan-out)

    /// <summary>
    /// v8 and v9 share a shape for migration purposes: both carry the
    /// project-wide <c>startOffsetFrames</c> and a per-item <c>tempoMap</c>. (v9
    /// widened <c>cueNumber</c> to a fractional value, which the current
    /// <c>Cue</c> already reads.)
    /// </summary>
    private static ProjectModel MigrateFromV8OrV9(LegacyV8 legacy)
    {
        var offset = legacy.TimecodeSettings.StartOffsetFrames;
        var defaultTypeId = legacy.CuePointTypes.Count > 0 ? legacy.CuePointTypes[0].Id : (Guid?)null;

        return new ProjectModel
        {
            Id = legacy.Id,
            Name = legacy.Name,
            CuePointTypes = legacy.CuePointTypes,
            Items = legacy.Items.Select(item => new MediaItem
            {
                Id = item.Id,
                Media = item.Media,
                Cues = ApplyLegacyTempoSectionsToCues(
                    item.TempoMap.Sections, NormalisedCues(item.Cues), defaultTypeId),
                StartTimecodeFrames = offset
            }).ToList(),
            ActiveItemId = legacy.ActiveItemId,
            TimecodeSettings = new ProjectTimecodeSettings { Framerate = legacy.TimecodeSettings.Framerate }
        };
    }

    /// <summary>v10 → current: tempo moves from <c>MediaItem.tempoMap</c> onto
    /// cues. Start TC and LTC mute are already per-item here.</summary>
    private static ProjectModel MigrateFromV10(LegacyV10 legacy)
    {
        var defaultTypeId = legacy.CuePointTypes.Count > 0 ? legacy.CuePointTypes[0].Id : (Guid?)null;

        return new ProjectModel
        {
            Id = legacy.Id,
            Name = legacy.Name,
            CuePointTypes = legacy.CuePointTypes,
            Items = legacy.Items.Select(item => new MediaItem
            {
                Id = item.Id,
                Media = item.Media,
                Cues = ApplyLegacyTempoSectionsToCues(
                    item.TempoMap.Sections, NormalisedCues(item.Cues), defaultTypeId),
                StartTimecodeFrames = item.StartTimecodeFrames,
                LtcMuted = item.LtcMuted
            }).ToList(),
            ActiveItemId = legacy.ActiveItemId,
            TimecodeSettings = legacy.TimecodeSettings
        };
    }

    private static List<Cue> NormalisedCues(List<Cue> cues)
    {
        foreach (var cue in cues)
        {
            cue.Clamped();
        }

        return cues;
    }

    /// <summary>
    /// Fans legacy tempo sections onto cues. Each section either lands its BPM on
    /// the nearest existing cue (within one beat) or appears as a new synthetic
    /// "Tempo" cue at its first downbeat. Returns the cues sorted by time.
    /// </summary>
    /// <remarks>
    /// The BPM copied from a section is deliberately <i>not</i> run through
    /// <see cref="Cue.Clamped"/>: Swift assigns it by direct property mutation
    /// here, bypassing its own clamping initialiser, and a re-implementation that
    /// quietly clamped would disagree on any legacy map with an out-of-range BPM.
    /// </remarks>
    private static List<Cue> ApplyLegacyTempoSectionsToCues(
        List<LegacyTempoSection> sections, List<Cue> cues, Guid? defaultTypeId)
    {
        var working = new List<Cue>(cues);

        // Sort by anchor time so out-of-order legacy input produces deterministic
        // output: two sections competing for the same cue resolve by anchor order.
        foreach (var section in sections.OrderBy(s => s.StartSeconds + s.DownbeatOffsetSeconds))
        {
            var anchor = section.StartSeconds + section.DownbeatOffsetSeconds;
            var tolerance = 60.0 / Math.Max(section.Bpm, 1);
            var index = NearestCueIndex(working, anchor, tolerance);

            if (index is { } found)
            {
                working[found].Bpm = section.Bpm;
                working[found].BeatsPerBar = section.BeatsPerBar;
            }
            else if (defaultTypeId is { } typeId)
            {
                working.Add(new Cue
                {
                    Id = Guid.NewGuid(),
                    TypeId = typeId,
                    CueNumber = null,
                    Name = "Tempo",
                    Time = anchor,
                    Notes = string.Empty,
                    FadeTime = FadeTime.Zero,
                    Bpm = section.Bpm,
                    BeatsPerBar = section.BeatsPerBar
                });
            }
        }

        return working.OrderBy(cue => cue.Time).ToList();
    }

    private static int? NearestCueIndex(List<Cue> cues, double time, double tolerance)
    {
        int? bestIndex = null;
        var bestDelta = double.PositiveInfinity;

        for (var index = 0; index < cues.Count; index++)
        {
            var delta = Math.Abs(cues[index].Time - time);
            if (delta <= tolerance && delta < bestDelta)
            {
                bestIndex = index;
                bestDelta = delta;
            }
        }

        return bestIndex;
    }

    // MARK: - Legacy decode shapes

    private sealed class VersionProbe
    {
        public int SchemaVersion { get; set; }
    }

    /// <summary>The pre-v10 shape of <c>timecodeSettings</c>: framerate plus the
    /// project-wide offset now carried per item.</summary>
    private sealed class LegacyPreV10TimecodeSettings
    {
        public SmpteFramerate Framerate { get; set; } = SmpteFramerate.Fps30;

        public int StartOffsetFrames { get; set; }
    }

    /// <summary>A v1/v2 cue: no type, no number, no fade.</summary>
    private sealed class LegacyCue
    {
        public Guid Id { get; set; }

        public string Name { get; set; } = string.Empty;

        public double Time { get; set; }

        public string Notes { get; set; } = string.Empty;

        public Cue ToCue(Guid typeId) => new()
        {
            Id = Id,
            TypeId = typeId,
            Name = Name,
            Time = Time,
            Notes = Notes,
            FadeTime = FadeTime.Zero
        };
    }

    /// <summary>A v3 cue: typed, but still numbered by the migration.</summary>
    private sealed class LegacyV3Cue
    {
        public Guid Id { get; set; }

        [JsonPropertyName("typeID")]
        public Guid TypeId { get; set; }

        public string Name { get; set; } = string.Empty;

        public double Time { get; set; }

        public string Notes { get; set; } = string.Empty;

        public Cue ToCue() => new()
        {
            Id = Id,
            TypeId = TypeId,
            Name = Name,
            Time = Time,
            Notes = Notes,
            FadeTime = FadeTime.Zero
        };
    }

    /// <summary>A v4 cue: numbered, but predating <c>fadeTime</c>.</summary>
    private sealed class LegacyV4Cue
    {
        public Guid Id { get; set; }

        [JsonPropertyName("typeID")]
        public Guid TypeId { get; set; }

        public double CueNumber { get; set; }

        public string Name { get; set; } = string.Empty;

        public double Time { get; set; }

        public string Notes { get; set; } = string.Empty;

        public Cue ToCue() => new()
        {
            Id = Id,
            TypeId = TypeId,
            CueNumber = CueNumber,
            Name = Name,
            Time = Time,
            Notes = Notes,
            FadeTime = FadeTime.Zero
        };
    }

    /// <summary>A v5 cue: the first with a persisted <c>fadeTime</c>.</summary>
    private sealed class LegacyV5Cue
    {
        public Guid Id { get; set; }

        [JsonPropertyName("typeID")]
        public Guid TypeId { get; set; }

        public double CueNumber { get; set; }

        public string Name { get; set; } = string.Empty;

        public double Time { get; set; }

        public string Notes { get; set; } = string.Empty;

        public FadeTime FadeTime { get; set; } = FadeTime.Zero;

        public Cue ToCue() => new()
        {
            Id = Id,
            TypeId = TypeId,
            CueNumber = CueNumber,
            Name = Name,
            Time = Time,
            Notes = Notes,
            FadeTime = FadeTime
        };
    }

    private sealed class LegacyV1
    {
        public Guid Id { get; set; }

        public string Name { get; set; } = string.Empty;

        /// <summary>v1 held one project-level media reference; <c>null</c> means an
        /// empty show.</summary>
        public MediaReference? Media { get; set; }

        public List<LegacyCue> Cues { get; set; } = [];
    }

    private sealed class LegacyV2
    {
        public Guid Id { get; set; }

        public string Name { get; set; } = string.Empty;

        public List<LegacyV2Item> Items { get; set; } = [];

        [JsonPropertyName("activeItemID")]
        public Guid? ActiveItemId { get; set; }
    }

    private sealed class LegacyV2Item
    {
        public Guid Id { get; set; }

        public MediaReference Media { get; set; } = new();

        public List<LegacyCue> Cues { get; set; } = [];
    }

    private sealed class LegacyV3
    {
        public Guid Id { get; set; }

        public string Name { get; set; } = string.Empty;

        public List<CuePointType> CuePointTypes { get; set; } = [];

        public List<LegacyV3Item> Items { get; set; } = [];

        [JsonPropertyName("activeItemID")]
        public Guid? ActiveItemId { get; set; }
    }

    private sealed class LegacyV3Item
    {
        public Guid Id { get; set; }

        public MediaReference Media { get; set; } = new();

        public List<LegacyV3Cue> Cues { get; set; } = [];
    }

    private sealed class LegacyV4
    {
        public Guid Id { get; set; }

        public string Name { get; set; } = string.Empty;

        public List<CuePointType> CuePointTypes { get; set; } = [];

        public List<LegacyV4Item> Items { get; set; } = [];

        [JsonPropertyName("activeItemID")]
        public Guid? ActiveItemId { get; set; }
    }

    private sealed class LegacyV4Item
    {
        public Guid Id { get; set; }

        public MediaReference Media { get; set; } = new();

        public List<LegacyV4Cue> Cues { get; set; } = [];
    }

    private sealed class LegacyV5
    {
        public Guid Id { get; set; }

        public string Name { get; set; } = string.Empty;

        public List<CuePointType> CuePointTypes { get; set; } = [];

        public List<LegacyV5Item> Items { get; set; } = [];

        [JsonPropertyName("activeItemID")]
        public Guid? ActiveItemId { get; set; }
    }

    private sealed class LegacyV5Item
    {
        public Guid Id { get; set; }

        public MediaReference Media { get; set; } = new();

        public List<LegacyV5Cue> Cues { get; set; } = [];
    }

    /// <summary>The v6/v7 item shape — current cues, but no <c>tempoMap</c> and
    /// no per-item start TC.</summary>
    private sealed class LegacyMediaItemPreV8
    {
        public Guid Id { get; set; }

        public MediaReference Media { get; set; } = new();

        public List<Cue> Cues { get; set; } = [];

        public MediaItem ToMediaItem(int startTimecodeFrames = 0) => NormaliseItem(new MediaItem
        {
            Id = Id,
            Media = Media,
            Cues = Cues,
            StartTimecodeFrames = startTimecodeFrames
        });
    }

    private sealed class LegacyV6
    {
        public Guid Id { get; set; }

        public string Name { get; set; } = string.Empty;

        public List<CuePointType> CuePointTypes { get; set; } = [];

        public List<LegacyMediaItemPreV8> Items { get; set; } = [];

        [JsonPropertyName("activeItemID")]
        public Guid? ActiveItemId { get; set; }
    }

    private sealed class LegacyV7
    {
        public Guid Id { get; set; }

        public string Name { get; set; } = string.Empty;

        public List<CuePointType> CuePointTypes { get; set; } = [];

        public List<LegacyMediaItemPreV8> Items { get; set; } = [];

        [JsonPropertyName("activeItemID")]
        public Guid? ActiveItemId { get; set; }

        public LegacyPreV10TimecodeSettings TimecodeSettings { get; set; } = new();
    }

    private sealed class LegacyV8
    {
        public Guid Id { get; set; }

        public string Name { get; set; } = string.Empty;

        public List<CuePointType> CuePointTypes { get; set; } = [];

        public List<LegacyV8Item> Items { get; set; } = [];

        [JsonPropertyName("activeItemID")]
        public Guid? ActiveItemId { get; set; }

        public LegacyPreV10TimecodeSettings TimecodeSettings { get; set; } = new();
    }

    private sealed class LegacyV8Item
    {
        public Guid Id { get; set; }

        public MediaReference Media { get; set; } = new();

        public List<Cue> Cues { get; set; } = [];

        public LegacyTempoMap TempoMap { get; set; } = new();
    }

    private sealed class LegacyV10
    {
        public Guid Id { get; set; }

        public string Name { get; set; } = string.Empty;

        public List<CuePointType> CuePointTypes { get; set; } = [];

        public List<LegacyV10Item> Items { get; set; } = [];

        [JsonPropertyName("activeItemID")]
        public Guid? ActiveItemId { get; set; }

        public ProjectTimecodeSettings TimecodeSettings { get; set; } = ProjectTimecodeSettings.Default();
    }

    private sealed class LegacyV10Item
    {
        public Guid Id { get; set; }

        public MediaReference Media { get; set; } = new();

        public List<Cue> Cues { get; set; } = [];

        public LegacyTempoMap TempoMap { get; set; } = new();

        public int StartTimecodeFrames { get; set; }

        public bool LtcMuted { get; set; }
    }

    private sealed class LegacyTempoMap
    {
        public List<LegacyTempoSection> Sections { get; set; } = [];
    }

    private sealed class LegacyTempoSection
    {
        public Guid Id { get; set; }

        public double StartSeconds { get; set; }

        public double Bpm { get; set; }

        public int BeatsPerBar { get; set; }

        public double DownbeatOffsetSeconds { get; set; }
    }
}
