using System.Text.Json.Serialization;
using OnlyCue.Core.Planning;

namespace OnlyCue.Core.Document;

/// <summary>Symmetric or split fade, in seconds. Mirrors Swift <c>FadeTime</c>.</summary>
/// <remarks>
/// <c>partial</c> so the text half — parsing and the two display spellings —
/// lives in <c>FadeTimeText.cs</c>, mirroring the split Swift already makes
/// between the stored properties and the <c>extension FadeTime</c> below them.
/// </remarks>
public sealed partial class FadeTime
{
    public double FadeIn { get; set; }

    public double FadeOut { get; set; }

    public static FadeTime Zero => Symmetric(0);

    public static FadeTime Symmetric(double seconds) => new() { FadeIn = seconds, FadeOut = seconds };

    /// <summary>
    /// Upper bound for a single fade leg, in seconds. Mirrors Swift
    /// <c>FadeTime.maximum</c> (#829).
    /// </summary>
    public const double Maximum = 3600;

    /// <summary>
    /// Coerces an untrusted seconds value into <c>0...Maximum</c>, as Swift's
    /// <c>FadeTime.init(from:)</c> does at the file boundary (#829). NaN and
    /// infinity defeat min/max, so they drop to zero rather than propagating.
    /// </summary>
    /// <remarks>
    /// Applied by <see cref="Cue.Clamped"/> rather than by the deserialiser,
    /// because that is where this port does the work Swift's decoding
    /// initialisers do. Deliberately <i>not</i> applied to in-process
    /// construction: the MA2 golden vectors seat an out-of-range fade on purpose
    /// to pin cross-platform formatter parity.
    /// </remarks>
    public static double Clamped(double seconds) =>
        double.IsFinite(seconds) ? Math.Min(Math.Max(seconds, 0), Maximum) : 0;
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
        // Coerced to null, not clamped: a number outside grandMA2's window means
        // nothing, and clamping would invent one the designer never chose (#830).
        CueNumber = CueNumber is { } number && CueNumberDomain.IsInDomain(number) ? number : (double?)null;
        FadeTime = new FadeTime
        {
            FadeIn = Document.FadeTime.Clamped(FadeTime.FadeIn),
            FadeOut = Document.FadeTime.Clamped(FadeTime.FadeOut)
        };
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
