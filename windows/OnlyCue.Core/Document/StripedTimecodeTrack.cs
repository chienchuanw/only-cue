using System.Text.Json.Serialization;

namespace OnlyCue.Core.Document;

/// <summary>
/// The SMPTE timecode striped onto a media file's audio, expressed as an anchor
/// (timecode at a known playback position) plus the assumption that LTC is
/// linear. Mirrors Swift <c>StripedTimecodeTrack</c>.
/// </summary>
/// <remarks>
/// Only the persisted shape and the pure queries are ported. Constructing a
/// track from decoded audio frames belongs to the LTC reader, which the Windows
/// port has not reached yet.
/// </remarks>
public sealed class StripedTimecodeTrack
{
    /// <summary>Timecode at <see cref="AnchorPlaybackSeconds"/>.</summary>
    public Timecode AnchorTimecode { get; set; }

    public double AnchorPlaybackSeconds { get; set; }

    /// <summary>Zero-based index of the audio channel carrying LTC.</summary>
    [JsonPropertyName("ltcChannel")]
    public int LtcChannel { get; set; }

    /// <summary>First playback second at which this track's timecode is real.
    /// <c>null</c> = unbounded — either not yet measured, or loaded from a
    /// document saved before #793.</summary>
    public double? ValidFrom { get; set; }

    /// <summary>Last playback second at which this track's timecode is real.
    /// <c>null</c> = unbounded.</summary>
    public double? ValidUntil { get; set; }

    /// <summary>Whether the timecode reported at <paramref name="seconds"/> was
    /// actually measured, as opposed to extrapolated past the end of the stripe.
    /// Unbounded on either side means "assume valid".</summary>
    public bool IsValidAt(double seconds)
    {
        if (ValidFrom is { } from && seconds < from)
        {
            return false;
        }

        return !(ValidUntil is { } until && seconds > until);
    }

    /// <summary>The striped timecode at <paramref name="seconds"/> of playback —
    /// the anchor shifted by the elapsed frame count, rounded.</summary>
    public Timecode TimecodeAt(double seconds)
    {
        var framesPerSecond = AnchorTimecode.Rate.FramesPerSecond();
        var frameDelta = (int)Math.Round(
            (seconds - AnchorPlaybackSeconds) * framesPerSecond, MidpointRounding.AwayFromZero);
        return Timecode.FromFrameCount(AnchorTimecode.FrameCount + frameDelta, AnchorTimecode.Rate);
    }
}
