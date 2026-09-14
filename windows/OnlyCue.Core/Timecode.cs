namespace OnlyCue.Core;

/// <summary>Stub — implemented once the golden verifier is red.</summary>
public readonly record struct Timecode
{
    public SmpteFramerate Rate => throw new NotImplementedException();
    public int Hours => throw new NotImplementedException();
    public int Minutes => throw new NotImplementedException();
    public int Seconds => throw new NotImplementedException();
    public int Frames => throw new NotImplementedException();
    public int FrameCount => throw new NotImplementedException();
    public double TotalSeconds => throw new NotImplementedException();
    public string DisplayString => throw new NotImplementedException();

    public static Timecode? Create(int hours, int minutes, int seconds, int frames, SmpteFramerate rate)
        => throw new NotImplementedException();

    public static Timecode FromFrameCount(int frameCount, SmpteFramerate rate)
        => throw new NotImplementedException();

    public static Timecode FromTotalSeconds(double totalSeconds, SmpteFramerate rate)
        => throw new NotImplementedException();

    public static Timecode? Parse(string text, SmpteFramerate rate)
        => throw new NotImplementedException();
}
