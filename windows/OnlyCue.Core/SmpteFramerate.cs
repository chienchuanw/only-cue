namespace OnlyCue.Core;

/// <summary>
/// The SMPTE frame rates OnlyCue supports. Mirrors the Swift
/// <c>SMPTEFramerate</c> (<c>OnlyCue/LTC/SMPTEFramerate.swift</c>); the
/// <see cref="RawValue"/> strings are the cross-platform contract keys used by
/// <c>golden/timecode-v1.json</c>.
/// </summary>
public enum SmpteFramerate
{
    Fps24,
    Fps25,
    Fps30,
    Fps30Drop
}

public static class SmpteFramerateExtensions
{
    /// <summary>The nominal frame count per second — 30 for drop-frame, which
    /// labels frames at 30 and drops numbers rather than changing the base.</summary>
    public static int FramesPerSecond(this SmpteFramerate rate) => rate switch
    {
        SmpteFramerate.Fps24 => 24,
        SmpteFramerate.Fps25 => 25,
        SmpteFramerate.Fps30 => 30,
        SmpteFramerate.Fps30Drop => 30,
        _ => throw new ArgumentOutOfRangeException(nameof(rate))
    };

    public static bool IsDropFrame(this SmpteFramerate rate) => rate == SmpteFramerate.Fps30Drop;

    /// <summary>The contract key as written in the golden vectors.</summary>
    public static string RawValue(this SmpteFramerate rate) => rate switch
    {
        SmpteFramerate.Fps24 => "24",
        SmpteFramerate.Fps25 => "25",
        SmpteFramerate.Fps30 => "30",
        SmpteFramerate.Fps30Drop => "30df",
        _ => throw new ArgumentOutOfRangeException(nameof(rate))
    };

    /// <summary>
    /// The rate with this nominal frames-per-second and drop-frame flag, or
    /// <c>null</c> if there is none (drop-frame only exists at 30 fps; only
    /// 24 / 25 / 30 are supported). Used when recovering a rate from a decoded
    /// LTC signal: the magnitude comes from the measured bit period, the
    /// drop-frame bit from the frame itself.
    /// </summary>
    public static SmpteFramerate? Matching(int framesPerSecond, bool isDropFrame)
    {
        if (isDropFrame)
        {
            return framesPerSecond == 30 ? SmpteFramerate.Fps30Drop : null;
        }

        return framesPerSecond switch
        {
            24 => SmpteFramerate.Fps24,
            25 => SmpteFramerate.Fps25,
            30 => SmpteFramerate.Fps30,
            _ => null
        };
    }

    public static SmpteFramerate FromRawValue(string rawValue) => rawValue switch
    {
        "24" => SmpteFramerate.Fps24,
        "25" => SmpteFramerate.Fps25,
        "30" => SmpteFramerate.Fps30,
        "30df" => SmpteFramerate.Fps30Drop,
        _ => throw new ArgumentException($"unknown framerate '{rawValue}'", nameof(rawValue))
    };
}
