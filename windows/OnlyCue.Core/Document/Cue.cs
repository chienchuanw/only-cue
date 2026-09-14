using System.Text.Json.Serialization;

namespace OnlyCue.Core.Document;

/// <summary>Symmetric or split fade, in seconds. Mirrors Swift <c>FadeTime</c>.</summary>
public sealed class FadeTime
{
    public double FadeIn { get; set; }

    public double FadeOut { get; set; }

    public static FadeTime Zero => Symmetric(0);

    public static FadeTime Symmetric(double seconds) => new() { FadeIn = seconds, FadeOut = seconds };
}

/// <summary>
/// A cue point on a media item. Mirrors Swift <c>Cue</c>
/// (<c>OnlyCue/Document/Cue.swift</c>).
/// </summary>
public sealed class Cue
{
    public Guid Id { get; set; }

    [JsonPropertyName("typeID")]
    public Guid TypeId { get; set; }

    /// <summary>Fractional since schema v9; <c>null</c> on the synthetic cues the
    /// v8–v10 tempo fan-out inserts.</summary>
    public double? CueNumber { get; set; }

    public string Name { get; set; } = string.Empty;

    public double Time { get; set; }

    public string Notes { get; set; } = string.Empty;

    public FadeTime FadeTime { get; set; } = FadeTime.Zero;

    /// <summary>Beats per minute, clamped to 20…400 on the way in (see
    /// <see cref="Clamped"/>).</summary>
    public double? Bpm { get; set; }

    public int? BeatsPerBar { get; set; }

    /// <summary>
    /// Normalises <see cref="Bpm"/> / <see cref="BeatsPerBar"/> exactly as Swift's
    /// clamping <c>Cue.init</c> does, so an out-of-range value on disk (a
    /// hand-edited document, a future-format leak) can't propagate into the grid
    /// computations. NaN and infinity drop to <c>null</c> rather than clamping,
    /// because either would defeat the min/max in the first place.
    /// </summary>
    /// <remarks>
    /// Swift routes every <i>decode</i> through that initialiser. Here the
    /// deserialiser fills the properties directly, so the codec calls this
    /// immediately afterwards — the one place cue decoding happens.
    /// </remarks>
    public Cue Clamped()
    {
        Bpm = Bpm is { } bpm && double.IsFinite(bpm) ? Math.Min(Math.Max(bpm, 20), 400) : null;
        BeatsPerBar = BeatsPerBar is { } beats ? Math.Max(1, Math.Min(beats, 16)) : null;
        return this;
    }
}

/// <summary>
/// A user-defined cue category. Mirrors Swift <c>CuePointType</c>.
/// </summary>
public sealed class CuePointType
{
    public Guid Id { get; set; }

    public string Name { get; set; } = string.Empty;

    public string ColorHex { get; set; } = string.Empty;

    public double DefaultFadeTime { get; set; }

    public string DefaultNamePattern { get; set; } = "Cue";

    /// <summary>Digit hotkey, or <c>null</c> when unbound.</summary>
    public int? Hotkey { get; set; }

    public bool IsVisible { get; set; } = true;

    public bool IsExportEnabled { get; set; } = true;
}
