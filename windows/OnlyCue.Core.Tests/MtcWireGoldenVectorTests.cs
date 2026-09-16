using OnlyCue.Core.Midi;
using Xunit;

namespace OnlyCue.Core.Tests;

/// <summary>
/// The Windows half of the MTC wire-format contract (epic #728, M2 slice 1).
/// macOS emits <c>golden/mtc-wire-v1.json</c> from the Swift <c>MTCFrame</c>;
/// this suite asserts the C# re-implementation reproduces every case exactly, so
/// drift between the two hand-maintained cores fails CI instead of shipping.
/// </summary>
public class MtcWireGoldenVectorTests
{
    private static readonly MtcWireVector Vector = MtcWireVector.Load();

    public static TheoryData<string> CaseLabels
    {
        get
        {
            var data = new TheoryData<string>();
            foreach (var label in Vector.Cases.Select(c => c.Label))
            {
                data.Add(label);
            }

            return data;
        }
    }

    [Fact]
    public void GoldenFile_IsTheExpectedContract()
    {
        Assert.Equal("mtc-wire", Vector.Contract);
        Assert.Equal(1, Vector.Version);
        Assert.NotEmpty(Vector.Cases);
    }

    [Theory]
    [MemberData(nameof(CaseLabels))]
    public void CSharpCore_ReproducesGoldenCase(string label)
    {
        var goldenCase = Vector.Cases.Single(c => c.Label == label);
        var rate = SmpteFramerateExtensions.FromRawValue(goldenCase.Rate);

        switch (goldenCase.Op)
        {
            case "rateBits":
                Assert.Equal(ExpectedByte(goldenCase), MtcFrame.RateBits(rate));
                break;
            case "quarterFrame":
                Assert.Equal(
                    ExpectedByte(goldenCase),
                    MtcFrame.QuarterFrameByte(RequiredPiece(goldenCase), TimecodeFrom(goldenCase, rate)));
                break;
            case "quarterFrameSequence":
                Assert.Equal(ExpectedBytes(goldenCase), SequenceBytes(TimecodeFrom(goldenCase, rate)));
                break;
            case "fullFrame":
                Assert.Equal(
                    ExpectedBytes(goldenCase),
                    MtcFrame.FullFrameBytes(TimecodeFrom(goldenCase, rate)).Select(b => (int)b));
                break;
            default:
                throw new InvalidDataException($"unknown golden op '{goldenCase.Op}'");
        }
    }

    /// <summary>The whole eight-message stream, status bytes included — the
    /// spelling the contract uses.</summary>
    private static IEnumerable<int> SequenceBytes(Timecode timecode) =>
        Enumerable.Range(0, MtcFrame.PiecesPerTimecode)
            .SelectMany(piece => MtcFrame.QuarterFrameMessage(piece, timecode))
            .Select(b => (int)b);

    private static byte ExpectedByte(MtcWireCase goldenCase) =>
        (byte)(goldenCase.Expect.Byte ?? throw new InvalidDataException($"{goldenCase.Label} has no expected byte"));

    private static IEnumerable<int> ExpectedBytes(MtcWireCase goldenCase) =>
        goldenCase.Expect.Bytes ?? throw new InvalidDataException($"{goldenCase.Label} has no expected bytes");

    private static int RequiredPiece(MtcWireCase goldenCase) =>
        goldenCase.Input.Piece ?? throw new InvalidDataException($"{goldenCase.Label} has no piece index");

    private static Timecode TimecodeFrom(MtcWireCase goldenCase, SmpteFramerate rate)
    {
        var input = goldenCase.Input;
        return Timecode.Create(
                   input.Hours ?? throw new InvalidDataException($"{goldenCase.Label} has no hours"),
                   input.Minutes ?? throw new InvalidDataException($"{goldenCase.Label} has no minutes"),
                   input.Seconds ?? throw new InvalidDataException($"{goldenCase.Label} has no seconds"),
                   input.Frames ?? throw new InvalidDataException($"{goldenCase.Label} has no frames"),
                   rate)
               ?? throw new InvalidDataException($"{goldenCase.Label} does not name a valid timecode");
    }

    /// <summary>
    /// Independent hand-computed pins, mirroring <c>test_knownWireValues</c> on
    /// the Swift side. Without these a wrong C# implementation could still be
    /// "verified" if the golden file were ever regenerated from a wrong source.
    /// </summary>
    [Fact]
    public void KnownWireValues_MatchTheMtcSpec()
    {
        // 00:00:00:00 at 24 fps: every payload nibble is zero, so each byte is
        // just its piece index in the high nibble.
        var zero = Timecode.Create(0, 0, 0, 0, SmpteFramerate.Fps24)!.Value;
        Assert.Equal(
            new byte[] { 0x00, 0x10, 0x20, 0x30, 0x40, 0x50, 0x60, 0x70 },
            Enumerable.Range(0, 8).Select(piece => MtcFrame.QuarterFrameByte(piece, zero)));
        Assert.Equal(
            new byte[] { 0xF0, 0x7F, 0x7F, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00, 0xF7 },
            MtcFrame.FullFrameBytes(zero));

        // 17:30:45:12 at 25 fps. Rate bits 0b01; hours 17 = 0b10001, so piece 6
        // carries 0b0001 and piece 7 carries (0b01 << 1) | 1 = 0b011.
        var interior = Timecode.Create(17, 30, 45, 12, SmpteFramerate.Fps25)!.Value;
        Assert.Equal(
            new byte[] { 0x0C, 0x10, 0x2D, 0x32, 0x4E, 0x51, 0x61, 0x73 },
            Enumerable.Range(0, 8).Select(piece => MtcFrame.QuarterFrameByte(piece, interior)));
        // Full Frame packs the rate above the hour: (0b01 << 5) | 17 = 0x31.
        Assert.Equal(
            new byte[] { 0xF0, 0x7F, 0x7F, 0x01, 0x01, 0x31, 30, 45, 12, 0xF7 },
            MtcFrame.FullFrameBytes(interior));
    }

    /// <summary>
    /// Every quarter-frame byte must stay a byte. In C# the operands of
    /// <c>&lt;&lt;</c> promote to <c>int</c>, so a missing cast in piece 7 —
    /// where the rate bits sit next to the hour's high bit — is exactly the kind
    /// of silent widening the vectors exist to catch.
    /// </summary>
    [Fact]
    public void EveryQuarterFrameByte_FitsTheStatusDataLayout()
    {
        foreach (var rate in Enum.GetValues<SmpteFramerate>())
        {
            var timecode = Timecode.Create(23, 59, 59, rate.FramesPerSecond() - 1, rate)!.Value;
            for (var piece = 0; piece < MtcFrame.PiecesPerTimecode; piece++)
            {
                var value = MtcFrame.QuarterFrameByte(piece, timecode);
                Assert.Equal(piece, value >> 4);            // high nibble names the piece
                Assert.True(value < 0x80, $"{rate} piece {piece}: data bytes have bit 7 clear");
            }
        }
    }

    /// <summary>The clamp is contract, not an accident: an out-of-range piece
    /// index must produce the nearest valid piece's byte rather than a byte
    /// whose high nibble names a piece nobody asked for.</summary>
    [Fact]
    public void OutOfRangePieces_ClampToTheEnds()
    {
        foreach (var rate in Enum.GetValues<SmpteFramerate>())
        {
            var timecode = Timecode.Create(23, 59, 59, rate.FramesPerSecond() - 1, rate)!.Value;
            Assert.Equal(MtcFrame.QuarterFrameByte(0, timecode), MtcFrame.QuarterFrameByte(-1, timecode));
            Assert.Equal(MtcFrame.QuarterFrameByte(7, timecode), MtcFrame.QuarterFrameByte(8, timecode));
        }
    }
}
