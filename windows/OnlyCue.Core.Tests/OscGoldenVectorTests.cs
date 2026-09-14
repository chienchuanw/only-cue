using OnlyCue.Core.Osc;
using Xunit;

namespace OnlyCue.Core.Tests;

/// <summary>
/// The Windows half of the OSC contract (epic #728, M1c — vector 6). macOS emits
/// <c>golden/osc-v1.json</c> from the Swift <c>OSCParser</c> /
/// <c>OSCCommand.from</c>; this suite asserts the C# re-implementation reproduces
/// every case, so drift between the two hand-maintained cores fails CI instead of
/// shipping.
/// </summary>
public class OscGoldenVectorTests
{
    private static readonly OscVector Vector = OscVector.Load();

    public static TheoryData<string> CaseNames => Names(Vector.Cases.Select(c => c.Name));

    [Fact]
    public void GoldenFile_IsTheExpectedContract()
    {
        Assert.Equal("osc", Vector.Contract);
        Assert.Equal(1, Vector.Version);
        Assert.NotEmpty(Vector.Cases);
    }

    [Theory]
    [MemberData(nameof(CaseNames))]
    public void Datagram_ParsesToGoldenMessages(string name)
    {
        var golden = Vector.Cases.Single(c => c.Name == name);

        var actual = OscParser.ParseMessages(Convert.FromBase64String(golden.Datagram));

        Assert.True(
            golden.Messages.Count == actual.Count,
            $"'{name}': expected {golden.Messages.Count} message(s), got {actual.Count} "
            + $"[{string.Join(", ", actual.Select(m => m.AddressPattern))}]");

        foreach (var (expected, message) in golden.Messages.Zip(actual))
        {
            Assert.True(
                expected.Address == message.AddressPattern,
                $"'{name}': expected address {expected.Address}, got {message.AddressPattern}");
            Assert.True(
                expected.Arguments.Count == message.Arguments.Count,
                $"'{name}' ({expected.Address}): expected {expected.Arguments.Count} argument(s), "
                + $"got {message.Arguments.Count}");

            foreach (var (expectedArgument, argument) in expected.Arguments.Zip(message.Arguments))
            {
                AssertArgument(name, expected.Address, expectedArgument, argument);
            }
        }
    }

    [Theory]
    [MemberData(nameof(CaseNames))]
    public void Datagram_MapsToGoldenCommand(string name)
    {
        var golden = Vector.Cases.Single(c => c.Name == name);

        var message = OscParser.Parse(Convert.FromBase64String(golden.Datagram));
        var actual = message is null ? null : OscCommand.From(message);

        if (golden.Command is not { } expected)
        {
            Assert.True(actual is null, $"'{name}': expected no command, got {actual}");
            return;
        }

        Assert.True(actual is not null, $"'{name}': expected command {expected.Kind}, got none");
        Assert.True(
            Enum.Parse<OscCommandKind>(expected.Kind, ignoreCase: true) == actual!.Kind,
            $"'{name}': expected command {expected.Kind}, got {actual.Kind}");
        Assert.True(
            GoldenDouble.BitwiseEquals(GoldenDouble.ParseOrNull(expected.Seconds), actual.Seconds),
            $"'{name}': expected {GoldenDouble.Describe(GoldenDouble.ParseOrNull(expected.Seconds))} seconds, "
            + $"got {GoldenDouble.Describe(actual.Seconds)}");
    }

    /// <summary>
    /// The contract's other half: a datagram off the network may be anything at
    /// all, and the parser must stay bounded and silent rather than throwing or
    /// spinning. Mutating the vector's own datagrams reaches far deeper into the
    /// branch structure than random bytes would — every truncation point and every
    /// single-byte corruption of a known-good message, which is where the length
    /// prefixes, pad arithmetic and bundle sizes live.
    /// </summary>
    [Fact]
    public void Parser_NeverThrows_OnTruncatedOrCorruptedDatagrams()
    {
        foreach (var datagram in Vector.Cases.Select(c => Convert.FromBase64String(c.Datagram)))
        {
            for (var length = 0; length <= datagram.Length; length++)
            {
                OscParser.ParseMessages(datagram.AsSpan(0, length));
            }

            for (var index = 0; index < datagram.Length; index++)
            {
                var corrupted = (byte[])datagram.Clone();
                corrupted[index] ^= 0xFF;
                OscParser.ParseMessages(corrupted);
            }
        }
    }

    private static void AssertArgument(string name, string address, VectorOscArgument expected, OscArgument actual)
    {
        var where = $"'{name}' ({address})";
        Assert.True(
            Enum.Parse<OscArgumentType>(expected.Type, ignoreCase: true) == actual.Type,
            $"{where}: expected a {expected.Type} argument, got {actual.Type}");

        switch (actual.Type)
        {
            case OscArgumentType.Int32:
                Assert.True(expected.Int == actual.IntValue, $"{where}: expected {expected.Int}, got {actual.IntValue}");
                break;
            case OscArgumentType.Float32:
                // Bitwise, not ==: the vector pins a -0.0 float argument, which
                // == cannot tell from 0.0. Widening binary32 to binary64 is
                // exact, so comparing as doubles loses nothing.
                Assert.True(
                    GoldenDouble.BitwiseEquals(GoldenDouble.Parse(expected.Float!), actual.FloatValue),
                    $"{where}: expected {GoldenDouble.Describe(GoldenDouble.Parse(expected.Float!))}, "
                    + $"got {GoldenDouble.Describe(actual.FloatValue)}");
                break;
            case OscArgumentType.String:
                Assert.True(
                    expected.Text == actual.StringValue,
                    $"{where}: expected \"{expected.Text}\", got \"{actual.StringValue}\"");
                break;
            default:
                // The four zero-byte types carry no payload; the type check above
                // is the whole assertion.
                break;
        }
    }

    private static TheoryData<string> Names(IEnumerable<string> names)
    {
        var data = new TheoryData<string>();
        foreach (var name in names)
        {
            data.Add(name);
        }

        return data;
    }
}
