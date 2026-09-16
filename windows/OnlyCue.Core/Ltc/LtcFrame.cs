namespace OnlyCue.Core.Ltc;

/// <summary>
/// One 80-bit SMPTE LTC frame (SMPTE 12M) as the bit sequence in <em>transmission
/// order</em> — <c>Bits[0]</c> is the first bit on the wire, and within each
/// multi-bit field the low-order bit comes first (LTC is LSB-first).
/// </summary>
/// <remarks>
/// Mirrors the Swift <c>LTCFrame</c> (<c>OnlyCue/LTC/LTCFrame.swift</c>); macOS is
/// the source of truth, with <c>golden/ltc-wire-v1.json</c> pinning the encode
/// direction and <c>golden/ltc-decode-v1.json</c> the read-back. The
/// <c>AVFoundation</c>-flavoured parts of the Swift file have no mirror; the
/// bit-level surface is complete in both directions.
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
    /// Wraps a raw 80-bit transmission-order word — the shape a decoder recovers,
    /// and the shape <c>golden/ltc-decode-v1.json</c>'s corruption recipes build
    /// by flipping bits in a well-formed frame. Swift traps on a wrong length
    /// (<c>precondition</c>); throwing keeps a bad caller failing on both sides.
    /// </summary>
    public static LtcFrame FromBits(IReadOnlyList<bool> bits)
    {
        if (bits.Count != BitCount)
        {
            throw new ArgumentException($"an LTC frame is exactly {BitCount} bits", nameof(bits));
        }

        return new LtcFrame([.. bits]);
    }

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

    // Decoded fields — LSB first within each BCD digit.

    public int Frames => Value(0, 4) + Value(8, 2) * 10;

    public int Seconds => Value(16, 4) + Value(24, 3) * 10;

    public int Minutes => Value(32, 4) + Value(40, 3) * 10;

    public int Hours => Value(48, 4) + Value(56, 2) * 10;

    public bool IsDropFrame => _bits[10];

    public bool HasEvenParity => _bits.Count(bit => bit) % 2 == 0;

    public bool SyncWordIsValid => _bits.Skip(64).Take(16).SequenceEqual(SyncWord);

    /// <summary><c>true</c> when the sync word is intact and the word has even
    /// parity — the two integrity checks a decoder applies before trusting the
    /// fields. Range is a <i>separate</i> gate: a well-formed word can still name
    /// no timecode (see <see cref="ToTimecode"/>), which
    /// <c>golden/ltc-decode-v1.json</c>'s <c>bcd-out-of-range</c> case pins.</summary>
    public bool IsWellFormed => SyncWordIsValid && HasEvenParity;

    /// <summary>
    /// The timecode this frame carries, at <paramref name="framesPerSecond"/>.
    /// The wire form only distinguishes drop-frame, via bit 10 — the rate
    /// magnitude comes from the signal's measured bit period, not from the word.
    /// <c>null</c> if the BCD fields are out of range (or name a
    /// drop-frame-skipped number), or if <paramref name="framesPerSecond"/> has
    /// no <see cref="SmpteFramerate"/>.
    /// </summary>
    public Timecode? ToTimecode(int framesPerSecond)
    {
        var rate = SmpteFramerateExtensions.Matching(framesPerSecond, IsDropFrame);
        return rate is null ? null : Timecode.Create(Hours, Minutes, Seconds, Frames, rate.Value);
    }

    private int Value(int start, int count)
    {
        var value = 0;
        for (var offset = 0; offset < count; offset++)
        {
            if (_bits[start + offset])
            {
                value |= 1 << offset;
            }
        }

        return value;
    }

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
