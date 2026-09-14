namespace OnlyCue.Core.Osc;

/// <summary>
/// A parsed OSC 1.0 message: an address pattern plus an ordered argument list.
/// OnlyCue is a receive-only OSC endpoint, so this is the only OSC value type
/// needed — there is no encoder. Mirrors the Swift <c>OSCMessage</c>
/// (<c>OnlyCue/OSC/OSCMessage.swift</c>), kept in lockstep by the golden-vector
/// contract (<c>golden/osc-v1.json</c>, epic #728 M1c).
/// </summary>
public sealed record OscMessage(string AddressPattern, IReadOnlyList<OscArgument> Arguments);

/// <summary>The OSC argument types OnlyCue understands.</summary>
public enum OscArgumentType
{
    Int32,
    Float32,
    String,
    True,
    False,
    Null,
    Impulse
}

/// <summary>
/// One OSC argument. The four zero-byte types (<c>T</c>/<c>F</c>/<c>N</c>/<c>I</c>)
/// carry no payload — senders use them for "go" buttons that transmit
/// <c>/onlycue/play T</c>.
/// </summary>
/// <remarks>
/// A flattened union rather than a class hierarchy, so the shape matches the
/// vector's JSON encoding and a case can be added without a new type. Note that
/// the compiler-generated record equality compares <see cref="FloatValue"/> with
/// <c>float.Equals</c>, which treats <c>-0.0f</c> and <c>0.0f</c> as equal — the
/// golden verifier therefore compares float arguments by bit pattern rather than
/// leaning on <c>==</c>.
/// </remarks>
public sealed record OscArgument
{
    private OscArgument(OscArgumentType type, int intValue, float floatValue, string? stringValue)
    {
        Type = type;
        IntValue = intValue;
        FloatValue = floatValue;
        StringValue = stringValue;
    }

    public OscArgumentType Type { get; }

    public int IntValue { get; }

    public float FloatValue { get; }

    public string? StringValue { get; }

    public static OscArgument True { get; } = new(OscArgumentType.True, 0, 0f, null);

    public static OscArgument False { get; } = new(OscArgumentType.False, 0, 0f, null);

    public static OscArgument Null { get; } = new(OscArgumentType.Null, 0, 0f, null);

    public static OscArgument Impulse { get; } = new(OscArgumentType.Impulse, 0, 0f, null);

    /// <summary>
    /// Numeric value if this argument is an int32 or float32; null otherwise.
    /// Lets command mapping treat "<c>/skip 5</c>" (int) and "<c>/skip 5.0</c>"
    /// (float) uniformly. Widening a binary32 to a binary64 is exact, so no
    /// precision is invented here.
    /// </summary>
    public double? NumericValue => Type switch
    {
        OscArgumentType.Int32 => IntValue,
        OscArgumentType.Float32 => FloatValue,
        _ => null
    };

    public static OscArgument Int32(int value) => new(OscArgumentType.Int32, value, 0f, null);

    public static OscArgument Float32(float value) => new(OscArgumentType.Float32, 0, value, null);

    public static OscArgument String(string value) => new(OscArgumentType.String, 0, 0f, value);
}
