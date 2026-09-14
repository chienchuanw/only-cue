using System.Globalization;

namespace OnlyCue.Core.Ma2;

/// <summary>
/// Encodes a cue's absolute timecode for a grandMA2 <c>Assign … /TrigTime=</c>
/// command (#683, Approach A). Mirrors Swift <c>MA2TrigTime</c>
/// (<c>OnlyCue/MA2/MA2TrigTime.swift</c>).
/// </summary>
public static class Ma2TrigTime
{
    /// <summary>
    /// Absolute time of <paramref name="cueTime"/> (seconds into the clip) as
    /// decimal seconds, snapped to the project frame grid and offset by the
    /// clip's start timecode.
    /// </summary>
    /// <remarks>
    /// <c>MidpointRounding.AwayFromZero</c> matches Swift's <c>.rounded()</c>;
    /// the default banker's mode would turn 0.5 s at 25 fps (exactly 12.5
    /// frames) into 12 instead of 13.
    /// </remarks>
    public static double Seconds(double cueTime, int startTimecodeFrames, SmpteFramerate framerate)
    {
        double fps = framerate.FramesPerSecond();
        var absFrames = startTimecodeFrames + (int)Math.Round(cueTime * fps, MidpointRounding.AwayFromZero);
        return absFrames / fps;
    }

    /// <summary>
    /// The <c>/TrigTime=</c> argument: <see cref="Seconds"/> as a trimmed decimal
    /// string (<c>"5"</c>, <c>"2.133333"</c>).
    /// </summary>
    public static string Command(double cueTime, int startTimecodeFrames, SmpteFramerate framerate)
    {
        var value = Seconds(cueTime, startTimecodeFrames, framerate);

        // Swift: `String(format: "%.6f", value)`. .NET's "F6" is the same
        // fixed-point, six-places form; both round from the exact binary value.
        var text = value.ToString("F6", CultureInfo.InvariantCulture);
        if (text.Contains('.'))
        {
            text = text.TrimEnd('0').TrimEnd('.');
        }

        return text;
    }
}
