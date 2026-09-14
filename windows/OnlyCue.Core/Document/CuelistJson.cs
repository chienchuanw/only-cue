using System.Text.Json;
using System.Text.Json.Serialization;

namespace OnlyCue.Core.Document;

/// <summary>
/// The single <see cref="JsonSerializerOptions"/> every <c>.cuelist</c> payload
/// is read and written with, configured so the JSON it produces is
/// byte-comparable with what Swift's <c>JSONEncoder</c> writes for the same
/// model.
/// </summary>
/// <remarks>
/// Three of Swift's conventions have to be reproduced deliberately:
/// <list type="bullet">
/// <item>camelCase property names — Swift's synthesised <c>CodingKeys</c> use
/// the property name verbatim, and every property in the model is already
/// camelCase. The policy also gets the acronym-tailed ones right
/// (<c>TypeID</c> → <c>typeID</c>, <c>RememberedLTC</c> → <c>rememberedLTC</c>).</item>
/// <item><c>null</c> is never written — Swift's synthesised <c>encode</c> uses
/// <c>encodeIfPresent</c> for optionals, so an absent value means an absent
/// key, not <c>"key": null</c>.</item>
/// <item>UUIDs are uppercase — Swift's <c>UUID</c> encodes via
/// <c>uuidString</c>, which is uppercase; .NET's default is lowercase.</item>
/// </list>
/// </remarks>
public static class CuelistJson
{
    public static JsonSerializerOptions Options { get; } = Build();

    private static JsonSerializerOptions Build()
    {
        var options = new JsonSerializerOptions
        {
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
            DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull
        };
        // Order matters: converters are matched first-wins, and the blanket enum
        // converter would otherwise claim SmpteFramerate and persist it by member
        // name ("fps30") instead of by its contract key ("30").
        options.Converters.Add(new SmpteFramerateJsonConverter());
        options.Converters.Add(new JsonStringEnumConverter(JsonNamingPolicy.CamelCase));
        options.Converters.Add(new UppercaseGuidConverter());
        options.Converters.Add(new TimecodeJsonConverter());
        return options;
    }
}

/// <summary>Writes <c>Guid</c> the way Swift's <c>UUID</c> does: uppercase,
/// hyphenated. Reads either case.</summary>
internal sealed class UppercaseGuidConverter : JsonConverter<Guid>
{
    public override Guid Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options) =>
        Guid.Parse(reader.GetString() ?? throw new JsonException("expected a UUID string"));

    public override void Write(Utf8JsonWriter writer, Guid value, JsonSerializerOptions options) =>
        writer.WriteStringValue(value.ToString("D").ToUpperInvariant());
}

/// <summary>Framerates persist as their contract keys (<c>"30df"</c>), not as
/// enum member names.</summary>
internal sealed class SmpteFramerateJsonConverter : JsonConverter<SmpteFramerate>
{
    public override SmpteFramerate Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options) =>
        SmpteFramerateExtensions.FromRawValue(
            reader.GetString() ?? throw new JsonException("expected a framerate string"));

    public override void Write(Utf8JsonWriter writer, SmpteFramerate value, JsonSerializerOptions options) =>
        writer.WriteStringValue(value.RawValue());
}

/// <summary>
/// <c>Timecode</c> persists as its displayed components plus the rate, matching
/// Swift's synthesised <c>Codable</c> on the struct's stored properties.
/// </summary>
/// <remarks>
/// One deliberate divergence: Swift's synthesised decode assigns the components
/// without validating them, while this side routes through
/// <see cref="Timecode.Create"/> and throws on a combination that cannot exist
/// at the given rate (frame 30 at 25 fps, a dropped drop-frame number). The C#
/// <c>Timecode</c> has no way to represent such a value, and a document
/// carrying one is corrupt rather than merely old — failing loudly beats
/// silently inventing a different timecode.
/// </remarks>
internal sealed class TimecodeJsonConverter : JsonConverter<Timecode>
{
    public override Timecode Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        using var document = JsonDocument.ParseValue(ref reader);
        var root = document.RootElement;
        var rate = SmpteFramerateExtensions.FromRawValue(
            root.GetProperty("rate").GetString() ?? throw new JsonException("timecode has no rate"));

        return Timecode.Create(
                   root.GetProperty("hours").GetInt32(),
                   root.GetProperty("minutes").GetInt32(),
                   root.GetProperty("seconds").GetInt32(),
                   root.GetProperty("frames").GetInt32(),
                   rate)
               ?? throw new JsonException($"{root.GetRawText()} is not a valid timecode at {rate.RawValue()}");
    }

    public override void Write(Utf8JsonWriter writer, Timecode value, JsonSerializerOptions options)
    {
        writer.WriteStartObject();
        writer.WriteNumber("hours", value.Hours);
        writer.WriteNumber("minutes", value.Minutes);
        writer.WriteNumber("seconds", value.Seconds);
        writer.WriteNumber("frames", value.Frames);
        writer.WriteString("rate", value.Rate.RawValue());
        writer.WriteEndObject();
    }
}
