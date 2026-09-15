using System.Buffers.Binary;
using System.Text;

namespace OnlyCue.Core.Osc;

/// <summary>
/// Minimal OSC 1.0 message parser — the subset OnlyCue needs as a receive-only
/// endpoint. A line-for-line re-implementation of the Swift <c>OSCParser</c>
/// (<c>OnlyCue/OSC/OSCParser.swift</c>), kept in lockstep by the golden-vector
/// contract (<c>golden/osc-v1.json</c>, epic #728 M1c).
/// </summary>
/// <remarks>
/// This is the only part of the core that reads untrusted bytes off the network,
/// so "never throws on garbage" is as much of the contract as "decodes valid
/// input correctly". Every malformed branch returns null or an empty list.
///
/// Five .NET defaults would each silently break parity with Swift and are
/// deliberately avoided here:
/// <list type="bullet">
/// <item>OSC is big-endian; <c>BitConverter.ToInt32</c> reads host order, so
/// <see cref="BinaryPrimitives"/> is used instead.</item>
/// <item><c>Encoding.UTF8.GetString</c> substitutes U+FFFD for invalid bytes and
/// returns a string where Swift's <c>String(data:encoding:.utf8)</c> returns nil,
/// so a strict throwing decoder is used and the throw is turned back into "no
/// message".</item>
/// <item>That same decoder <em>keeps</em> a leading U+FEFF where Swift's
/// NSString-backed one drops it, so <c>ReadOscString</c> strips one explicitly.</item>
/// <item>The <c>/</c> and <c>,</c> tests compare a <b>scalar</b> on both sides
/// (#836). They briefly compared grapheme clusters, to match Swift's
/// <c>hasPrefix</c>; that made the answer depend on each runtime's Unicode
/// Character Database, which is not the same table. See
/// <see cref="StartsWithScalar"/>.</item>
/// <item>Slicing must not re-base the NUL search: Swift searches to the end of
/// the datagram, not the end of the current field.</item>
/// </list>
///
/// Nesting depth is capped at <see cref="MaximumBundleDepth"/> on both sides
/// (#835). Before that cap, both parsers recursed once per bundle level with no
/// limit, so the datagram chose our stack depth: at 20 bytes per level a
/// 65507-byte UDP datagram buys 3275 levels (the innermost bundle carries no
/// size word, so depth D costs 20D-4 bytes), which survived a 1 MB stack — but
/// only because the UDP size limit happened to sit below it.
/// </remarks>
public static class OscParser
{
    private static readonly UTF8Encoding StrictUtf8 = new(encoderShouldEmitUTF8Identifier: false, throwOnInvalidBytes: true);

    private static readonly IReadOnlyList<OscMessage> None = [];

    /// <summary>
    /// Maximum <c>#bundle</c> nesting accepted. Mirrors Swift
    /// <c>OSCParser.maximumBundleDepth</c> and must stay equal to it — the two
    /// are pinned together at the boundary by <c>golden/osc-v1.json</c>.
    /// </summary>
    /// <remarks>
    /// The cap exists because a <see cref="StackOverflowException"/> cannot be
    /// caught on .NET: it terminates the process, so the overflow has to be
    /// prevented by refusing to recurse rather than handled once it happens.
    /// 32 is far above real traffic (senders nest one or two deep) and far
    /// below the depth that exhausts any stack the parser might run on. The
    /// exact number is not load-bearing; sharing it with macOS is.
    /// </remarks>
    public const int MaximumBundleDepth = 32;

    /// <summary>
    /// Parse a single datagram. For a bundle, returns the first contained message
    /// (sufficient for OnlyCue's command-per-button usage).
    /// </summary>
    public static OscMessage? Parse(ReadOnlySpan<byte> data)
    {
        var messages = ParseMessages(data);
        return messages.Count > 0 ? messages[0] : null;
    }

    /// <summary>
    /// Parse a datagram into zero or more messages. A plain message yields one; a
    /// <c>#bundle</c> yields its (recursively flattened) contents.
    /// </summary>
    public static IReadOnlyList<OscMessage> ParseMessages(ReadOnlySpan<byte> data) =>
        ParseMessages(data, depth: 0);

    /// <summary>
    /// <paramref name="depth"/> counts enclosing <c>#bundle</c> containers; the
    /// outermost body parses at depth 1. An over-deep element yields no messages
    /// but does not abandon the bundle containing it — the same rule a malformed
    /// element follows, so one hostile branch cannot silently drop its
    /// well-formed siblings.
    /// </summary>
    private static IReadOnlyList<OscMessage> ParseMessages(ReadOnlySpan<byte> data, int depth)
    {
        var reader = new Reader(data);
        if (reader.ReadOscString() is not { } head)
        {
            return None;
        }

        if (head == "#bundle")
        {
            return depth < MaximumBundleDepth ? ParseBundle(ref reader, depth + 1) : None;
        }

        if (!StartsWithScalar(head, '/'))
        {
            return None;
        }

        return ParsePlainMessage(head, ref reader) is { } message ? [message] : None;
    }

    /// <summary><c>#bundle</c> body: an 8-byte time tag, then
    /// <c>[Int32 size][element bytes]</c> × N. A malformed element contributes no
    /// messages but does not abandon the rest of the bundle; a non-positive or
    /// over-long size ends the loop, which is what keeps it bounded.</summary>
    private static IReadOnlyList<OscMessage> ParseBundle(ref Reader reader, int depth)
    {
        if (!reader.Skip(8))
        {
            return None;
        }

        var output = new List<OscMessage>();
        while (reader.Remaining >= 4)
        {
            if (reader.ReadInt32() is not { } size || size <= 0 || !reader.ReadBytes(size, out var element))
            {
                break;
            }

            output.AddRange(ParseMessages(element, depth));
        }

        return output;
    }

    /// <summary><paramref name="address"/> has already been read; consume the
    /// type-tag string and arguments. A message with no type-tag string is
    /// technically malformed in OSC 1.1+ but some senders omit it for no-arg
    /// messages, so the address-only form is accepted — as is a readable word
    /// that simply does not begin with a comma.</summary>
    private static OscMessage? ParsePlainMessage(string address, ref Reader reader)
    {
        if (reader.ReadOscString() is not { } typeTags || !StartsWithScalar(typeTags, ','))
        {
            return new OscMessage(address, []);
        }

        return ParseArguments(typeTags, ref reader) is { } arguments
            ? new OscMessage(address, arguments)
            : null;
    }

    /// <summary>One argument per tag after the leading comma. Returns null if any
    /// value is short or an unknown tag is hit, which drops the <em>whole</em>
    /// message rather than yielding a partially parsed one.</summary>
    /// <remarks>
    /// Swift iterates <c>Unicode.Scalar</c> where this iterates <c>char</c>
    /// (UTF-16 units). Those differ only on astral scalars, where Swift sees one
    /// item and this sees a surrogate pair — and since every known tag is a single
    /// ASCII letter, both sides hit "unknown tag" on the first of them and drop the
    /// whole message. The counts differ; the outcome cannot.
    ///
    /// What Swift must <b>not</b> do here is iterate <c>Character</c>. A
    /// <c>dropFirst()</c> over grapheme clusters would swallow a combining mark
    /// along with the leading comma, parsing <c>","</c> + U+0301 as a valid
    /// zero-argument list while this loop still saw U+0301 as an unknown tag. That
    /// is why #836 changed both the prefix test and the Swift loop together.
    /// </remarks>
    private static List<OscArgument>? ParseArguments(string typeTags, ref Reader reader)
    {
        var arguments = new List<OscArgument>();
        foreach (var tag in typeTags.AsSpan(1))
        {
            if (ParseArgument(tag, ref reader) is not { } argument)
            {
                return null;
            }

            arguments.Add(argument);
        }

        return arguments;
    }

    /// <summary>Does this OSC-string begin with <paramref name="expected"/>?
    /// OSC is a byte protocol — "the address pattern begins with the character
    /// <c>/</c>" means byte 0x2F — so this is a scalar comparison, and Swift's
    /// <c>startsWithScalar</c> is the same comparison.</summary>
    /// <remarks>
    /// This used to ask a grapheme-cluster question, via
    /// <c>StringInfo.GetNextTextElementLength</c>, so that it matched Swift's
    /// <c>hasPrefix</c>. Matching it that way was the mistake: UAX #29 runs against
    /// whatever Unicode Character Database the runtime carries, and the two are not
    /// the same table — .NET 10 ships UCD 16.0, Swift 6.3 on macOS 26 ships UCD
    /// 17.0. 42 combining scalars joined the leading cluster on one side and not the
    /// other, and no golden case could pin that: it would have gone red on a
    /// toolchain upgrade rather than on a regression. Comparing scalars deletes the
    /// Unicode table from the parser instead of trying to synchronise two of them
    /// (#836).
    ///
    /// <paramref name="expected"/> is a <c>char</c>, and only ever <c>/</c> or
    /// <c>,</c>. Both are ASCII and therefore one UTF-16 unit, so comparing
    /// <c>value[0]</c> really is comparing the first scalar; there is no surrogate
    /// case to worry about.
    /// </remarks>
    private static bool StartsWithScalar(string value, char expected) =>
        value.Length > 0 && value[0] == expected;

    private static OscArgument? ParseArgument(char tag, ref Reader reader) => tag switch
    {
        'i' => reader.ReadInt32() is { } value ? OscArgument.Int32(value) : null,
        'f' => reader.ReadFloat32() is { } value ? OscArgument.Float32(value) : null,
        's' => reader.ReadOscString() is { } value ? OscArgument.String(value) : null,
        'T' => OscArgument.True,
        'F' => OscArgument.False,
        'N' => OscArgument.Null,
        'I' => OscArgument.Impulse,
        _ => null
    };

    /// <summary>4-byte-aligned cursor over a datagram with the OSC primitives.</summary>
    private ref struct Reader(ReadOnlySpan<byte> data)
    {
        private readonly ReadOnlySpan<byte> data = data;
        private int offset = 0;

        public readonly int Remaining => data.Length - offset;

        public bool Skip(int count)
        {
            if (Remaining < count)
            {
                return false;
            }

            offset += count;
            return true;
        }

        public bool ReadBytes(int count, out ReadOnlySpan<byte> slice)
        {
            if (Remaining < count)
            {
                slice = default;
                return false;
            }

            slice = data.Slice(offset, count);
            offset += count;
            return true;
        }

        /// <summary>Null-terminated, then padded with NULs to the next 4-byte
        /// boundary. The NUL is searched for to the end of the datagram, not the
        /// end of any notional field.</summary>
        public string? ReadOscString()
        {
            var length = data[offset..].IndexOf((byte)0);
            if (length < 0)
            {
                return null;
            }

            string value;
            try
            {
                value = StrictUtf8.GetString(data.Slice(offset, length));
            }
            catch (DecoderFallbackException)
            {
                // Swift's `String(data:encoding:.utf8)` returns nil for these
                // bytes; the default .NET decoder would substitute U+FFFD and
                // accept the datagram.
                return null;
            }

            // `String(data:encoding:.utf8)` is NSString-backed and silently drops
            // exactly one *leading* U+FEFF; `UTF8Encoding.GetString` keeps it,
            // strict or lenient. Without this, a BOM-prefixed "#bundle" takes the
            // plain-message branch instead of the bundle branch, and a
            // BOM-prefixed address is rejected outright — the same datagram
            // driving the console on macOS and doing nothing on Windows.
            // Verified against Swift: one BOM only, leading position only.
            if (value.StartsWith('\uFEFF'))
            {
                value = value[1..];
            }

            var consumed = length + 1;
            var padded = (consumed + 3) & ~3;
            if (Remaining < padded)
            {
                return null;
            }

            offset += padded;
            return value;
        }

        public int? ReadInt32()
        {
            if (Remaining < 4)
            {
                return null;
            }

            var value = BinaryPrimitives.ReadInt32BigEndian(data.Slice(offset, 4));
            offset += 4;
            return value;
        }

        public float? ReadFloat32() =>
            ReadUInt32() is { } bits ? BitConverter.UInt32BitsToSingle(bits) : null;

        private uint? ReadUInt32()
        {
            if (Remaining < 4)
            {
                return null;
            }

            var value = BinaryPrimitives.ReadUInt32BigEndian(data.Slice(offset, 4));
            offset += 4;
            return value;
        }
    }
}
