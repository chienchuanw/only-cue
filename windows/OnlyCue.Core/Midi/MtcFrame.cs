namespace OnlyCue.Core.Midi;

/// <summary>
/// The MIDI Timecode wire format — pure byte encoding, no MIDI transport.
/// Mirrors the Swift <c>MTCFrame</c> (<c>OnlyCue/MIDI/MTCFrame.swift</c>); macOS
/// is the source of truth and <c>golden/mtc-wire-v1.json</c> is the contract.
/// </summary>
/// <remarks>
/// <para>
/// Two message shapes carry MTC: <b>quarter-frame</b> (<c>F1 &lt;data&gt;</c>),
/// the running stream, where a complete value takes eight messages and therefore
/// spans two frames; and <b>Full Frame</b>
/// (<c>F0 7F 7F 01 01 hh mm ss ff F7</c>), a Universal Real Time SysEx that jams
/// a receiver to an absolute position in one message.
/// </para>
/// <para>
/// <b>Rate bits are two bits wide</b> — MTC encodes exactly 24 / 25 / 29.97-DF /
/// 30 and has no 30-fps-drop-frame code, so <c>Fps30Drop</c> takes the 29.97-DF
/// slot while still being clocked at 30 fps (ADR-019, reaffirmed by ADR-032).
/// </para>
/// <para>
/// Every shift below is cast back to <c>byte</c> explicitly: in C# the operands
/// of <c>&lt;&lt;</c> and <c>&gt;&gt;</c> promote to <c>int</c>, so an
/// unintended width change is one missing cast away.
/// </para>
/// </remarks>
public static class MtcFrame
{
    /// <summary>Status byte introducing a quarter-frame message.</summary>
    public const byte QuarterFrameStatus = 0xF1;

    /// <summary>Quarter-frame messages needed to transmit one complete timecode.</summary>
    public const int PiecesPerTimecode = 8;

    /// <summary>Frames spanned by one full eight-message quarter-frame sequence.</summary>
    public const int FramesPerSequence = 2;

    /// <summary>The two-bit MTC rate code for <paramref name="rate"/>.</summary>
    public static byte RateBits(SmpteFramerate rate) => rate switch
    {
        SmpteFramerate.Fps24 => 0b00,
        SmpteFramerate.Fps25 => 0b01,
        SmpteFramerate.Fps30Drop => 0b10,   // 29.97 drop — the only drop-frame slot MTC has
        SmpteFramerate.Fps30 => 0b11,
        _ => throw new ArgumentOutOfRangeException(nameof(rate))
    };

    /// <summary>
    /// The data byte for quarter-frame <paramref name="piece"/> (0…7) of
    /// <paramref name="timecode"/>. Layout is <c>0nnn dddd</c>: <c>nnn</c> is the
    /// piece index, <c>dddd</c> the payload nibble. Pieces run
    /// least-significant-first — frames, seconds, minutes, hours — with the rate
    /// bits riding in piece 7 alongside the single high bit of the hour.
    /// </summary>
    /// <remarks><paramref name="piece"/> is <b>clamped</b> to 0…7 rather than
    /// rejected: an out-of-range index is a caller bug, and clamping keeps a
    /// malformed byte (one whose high nibble names a different piece) off the
    /// wire. Throwing here instead would be a silent divergence from macOS, so
    /// the golden vectors pin <c>-1</c> and <c>8</c> explicitly.</remarks>
    public static byte QuarterFrameByte(int piece, Timecode timecode)
    {
        var index = Math.Clamp(piece, 0, PiecesPerTimecode - 1);
        var payload = index switch
        {
            0 => (byte)(timecode.Frames & 0x0F),
            1 => (byte)((timecode.Frames >> 4) & 0x01),
            2 => (byte)(timecode.Seconds & 0x0F),
            3 => (byte)((timecode.Seconds >> 4) & 0x03),
            4 => (byte)(timecode.Minutes & 0x0F),
            5 => (byte)((timecode.Minutes >> 4) & 0x03),
            6 => (byte)(timecode.Hours & 0x0F),
            _ => (byte)((RateBits(timecode.Rate) << 1) | ((timecode.Hours >> 4) & 0x01))
        };

        return (byte)((index << 4) | payload);
    }

    /// <summary>The complete two-byte quarter-frame message.</summary>
    public static byte[] QuarterFrameMessage(int piece, Timecode timecode) =>
        [QuarterFrameStatus, QuarterFrameByte(piece, timecode)];

    /// <summary>
    /// The Universal Real Time SysEx that locates a receiver to
    /// <paramref name="timecode"/>: <c>F0 7F &lt;device&gt; 01 01 hh mm ss ff F7</c>,
    /// addressed to <c>0x7F</c> (all devices). The hour byte packs the rate bits
    /// above the hour: <c>(rateBits &lt;&lt; 5) | hh</c>.
    /// </summary>
    public static byte[] FullFrameBytes(Timecode timecode)
    {
        var hourByte = (byte)((RateBits(timecode.Rate) << 5) | (timecode.Hours & 0x1F));
        return
        [
            0xF0, 0x7F, 0x7F,   // SysEx start, Universal Real Time, all devices
            0x01, 0x01,         // sub-ID 1: MIDI Time Code — sub-ID 2: Full Message
            hourByte,
            (byte)timecode.Minutes,
            (byte)timecode.Seconds,
            (byte)timecode.Frames,
            0xF7                // SysEx end
        ];
    }
}
