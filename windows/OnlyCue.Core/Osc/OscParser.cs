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
/// Three .NET defaults would each silently break parity with Swift and are
/// deliberately avoided here:
/// <list type="bullet">
/// <item>OSC is big-endian; <c>BitConverter.ToInt32</c> reads host order, so
/// <see cref="BinaryPrimitives"/> is used instead.</item>
/// <item><c>Encoding.UTF8.GetString</c> substitutes U+FFFD for invalid bytes and
/// returns a string where Swift's <c>String(data:encoding:.utf8)</c> returns nil,
/// so a strict throwing decoder is used and the throw is turned back into "no
/// message".</item>
/// <item>Slicing must not re-base the NUL search: Swift searches to the end of
/// the datagram, not the end of the current field.</item>
/// </list>
/// </remarks>
public static class OscParser
{
    private static readonly UTF8Encoding StrictUtf8 = new(encoderShouldEmitUTF8Identifier: false, throwOnInvalidBytes: true);

    private static readonly IReadOnlyList<OscMessage> None = [];

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
    public static IReadOnlyList<OscMessage> ParseMessages(ReadOnlySpan<byte> data)
    {
        var reader = new Reader(data);
        if (reader.ReadOscString() is not { } head)
        {
            return None;
        }

        if (head == "#bundle")
        {
            return ParseBundle(ref reader);
        }

        if (!head.StartsWith('/'))
        {
            return None;
        }

        return ParsePlainMessage(head, ref reader) is { } message ? [message] : None;
    }

    /// <summary><c>#bundle</c> body: an 8-byte time tag, then
    /// <c>[Int32 size][element bytes]</c> × N. A malformed element contributes no
    /// messages but does not abandon the rest of the bundle; a non-positive or
    /// over-long size ends the loop, which is what keeps it bounded.</summary>
    private static IReadOnlyList<OscMessage> ParseBundle(ref Reader reader)
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

            output.AddRange(ParseMessages(element));
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
        if (reader.ReadOscString() is not { } typeTags || !typeTags.StartsWith(','))
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
    /// Swift iterates <c>Character</c> (grapheme clusters) where this iterates
    /// <c>char</c>. The two cannot diverge: a cluster of more than one scalar is
    /// never one of the seven single-ASCII-letter tags, so Swift rejects it, and
    /// C# rejects it too because no ASCII letter combines with a following scalar
    /// without that scalar itself being an invalid tag.
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
