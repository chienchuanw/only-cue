namespace OnlyCue.Core.Ltc;

/// <summary>
/// One 80-bit SMPTE LTC frame (SMPTE 12M) as the bit sequence in <em>transmission
/// order</em> — <c>Bits[0]</c> is the first bit on the wire, and within each
/// multi-bit field the low-order bit comes first (LTC is LSB-first).
/// </summary>
/// <remarks>
/// Mirrors the Swift <c>LTCFrame</c> (<c>OnlyCue/LTC/LTCFrame.swift</c>); macOS is
/// the source of truth and <c>golden/ltc-wire-v1.json</c> is the contract. Only
/// the wire surface the vectors pin is mirrored — the decode-side accessors the
/// Swift type carries for <c>LTCDecoder</c>'s benefit have no caller here yet.
/// </remarks>
public readonly struct LtcFrame
{
    public const int BitCount = 80;

    /// <summary>Fixed sync word, bits 64–79, transmission order:
    /// <c>00</c> · twelve <c>1</c>s · <c>01</c>.</summary>
    public static IReadOnlyList<bool> SyncWord { get; } = BuildSyncWord();

    private readonly bool[] _bits;

    private LtcFrame(bool[] bits) => _bits = bits;

    public IReadOnlyList<bool> Bits => _bits;

    /// <summary>
    /// The bit-polarity-correction (parity) position for <paramref name="rate"/>.
    /// SMPTE 12M swaps this bit with a binary-group flag between the 25 fps and
    /// the 24 / 30 fps layouts: at 25 fps the correction lives at bit 59 and bit
    /// 27 is BGF0; everywhere else the correction is at bit 27 and bit 59 is
    /// BGF2 (#853).
    /// </summary>
    public static int ParityBitIndex(SmpteFramerate rate) =>
        rate == SmpteFramerate.Fps25 ? 59 : 27;

    public static LtcFrame FromTimecode(Timecode timecode)
    {
        var word = new bool[BitCount];

        void WriteBcd(int value, int unitsAt, int unitsBits, int tensAt, int tensBits)
        {
            var units = value % 10;
            var tens = value / 10;
            for (var offset = 0; offset < unitsBits; offset++)
            {
                word[unitsAt + offset] = ((units >> offset) & 1) == 1;
            }

            for (var offset = 0; offset < tensBits; offset++)
            {
                word[tensAt + offset] = ((tens >> offset) & 1) == 1;
            }
        }

        WriteBcd(timecode.Frames, 0, 4, 8, 2);
        word[10] = timecode.Rate.IsDropFrame();
        WriteBcd(timecode.Seconds, 16, 4, 24, 3);
        WriteBcd(timecode.Minutes, 32, 4, 40, 3);
        WriteBcd(timecode.Hours, 48, 4, 56, 2);
        for (var offset = 0; offset < SyncWord.Count; offset++)
        {
            word[64 + offset] = SyncWord[offset];
        }

        if (word.Count(bit => bit) % 2 != 0)
        {
            word[ParityBitIndex(timecode.Rate)] = true;
        }

        return new LtcFrame(word);
    }

    public bool HasEvenParity => _bits.Count(bit => bit) % 2 == 0;

    public bool SyncWordIsValid => _bits.Skip(64).Take(16).SequenceEqual(SyncWord);

    /// <summary>The word as 80 <c>'0'</c> / <c>'1'</c> characters in transmission
    /// order — the spelling the golden vectors use.</summary>
    public string BitString() => string.Create(BitCount, _bits, static (span, bits) =>
    {
        for (var index = 0; index < bits.Length; index++)
        {
            span[index] = bits[index] ? '1' : '0';
        }
    });

    private static bool[] BuildSyncWord()
    {
        var word = new bool[16];
        for (var index = 2; index < 14; index++)
        {
            word[index] = true;
        }

        word[15] = true;
        return word;
    }
}
