using System.Globalization;
using OnlyCue.Core.Document;

namespace OnlyCue.Core.Ma2;

/// <summary>
/// Generates the grandMA2 sequence import XML (#683): one content-empty cue per
/// OnlyCue cue with number, label, info and fades. Mirrors Swift
/// <c>MA2SequenceXMLGenerator</c>
/// (<c>OnlyCue/MA2/MA2SequenceXMLGenerator.swift</c>).
/// </summary>
/// <remarks>
/// Hand-assembled from strings rather than built with <c>XmlWriter</c>, and that
/// is deliberate: the console's importer is matched against real v3.9.x exports,
/// so the contract is the exact byte sequence — self-closing tag spacing, tab
/// indentation, attribute order and the escaping set in <see cref="Escape"/>.
/// <c>XmlWriter</c> would normalise all four.
/// </remarks>
public static class Ma2SequenceXmlGenerator
{
    public static string Xml(IReadOnlyList<Cue> cues, string sequenceName, string showfile, string datetime)
    {
        // MA2 sequences are number-ordered; the timecode generator references
        // cues by this number-sorted 1-based index. Cue numbers need not be
        // monotonic with cue times in OnlyCue.
        var ordered = Ma2CueOrdering.ByNumber(cues);

        var lines = new List<string>
        {
            "<?xml version=\"1.0\" encoding=\"utf-8\"?>",
            "<?xml-stylesheet type=\"text/xsl\" href=\"styles/sequ@html@default.xsl\"?>",
            "<MA xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" "
                + "xmlns=\"http://schemas.malighting.de/grandma2/xml/MA\" "
                + "xsi:schemaLocation=\"http://schemas.malighting.de/grandma2/xml/MA "
                + "http://schemas.malighting.de/grandma2/xml/3.9.60/MA.xsd\" "
                + "major_vers=\"3\" minor_vers=\"9\" stream_vers=\"60\">",
            $"\t<Info datetime=\"{Escape(datetime)}\" showfile=\"{Escape(showfile)}\" />",
            $"\t<Sequ index=\"0\" name=\"{Escape(sequenceName)}\" "
                + "timecode_slot=\"255\" forced_position_mode=\"0\">",
            "\t\t<Cue xsi:nil=\"true\" />"  // cue-zero placeholder
        };

        for (var position = 0; position < ordered.Count; position++)
        {
            lines.AddRange(CueElement(ordered[position], position + 1));
        }

        lines.Add("\t</Sequ>");
        lines.Add("</MA>");
        return string.Join('\n', lines);
    }

    /// <summary>
    /// Minimal XML escaping for attribute values and text nodes.
    /// </summary>
    /// <remarks>
    /// Exactly four replacements, and the apostrophe is deliberately <b>not</b>
    /// one of them — matching the real console exports this was modelled on.
    /// <c>XmlWriter</c> and <c>SecurityElement.Escape</c> both escape <c>'</c>,
    /// which would put <c>&amp;apos;</c> in a file macOS writes literally, so
    /// neither may be substituted here. <c>&amp;</c> must stay first or it would
    /// re-escape the ampersands the later replacements introduce.
    /// </remarks>
    public static string Escape(string text) =>
        text.Replace("&", "&amp;")
            .Replace("<", "&lt;")
            .Replace(">", "&gt;")
            .Replace("\"", "&quot;");

    private static List<string> CueElement(Cue cue, int index)
    {
        var number = Ma2CueNumber.Split(cue.CueNumber ?? 0);
        var lines = new List<string>
        {
            $"\t\t<Cue index=\"{index.ToString(CultureInfo.InvariantCulture)}\">",
            $"\t\t\t<Number number=\"{number.Number.ToString(CultureInfo.InvariantCulture)}\" "
                + $"sub_number=\"{number.SubNumber.ToString(CultureInfo.InvariantCulture)}\" />",
            $"\t\t\t{CuePart(cue)}"
        };

        if (cue.Notes.Length > 0)
        {
            lines.Add("\t\t\t<InfoItems>");
            lines.Add($"\t\t\t\t<Info>{Escape(cue.Notes)}</Info>");
            lines.Add("\t\t\t</InfoItems>");
        }

        lines.Add("\t\t</Cue>");
        return lines;
    }

    /// <summary>
    /// All cue data (name, fades) lives on part 0 in MA2. Zero fades and empty
    /// names are omitted — the import fills defaults.
    /// </summary>
    private static string CuePart(Cue cue)
    {
        var attributes = new List<string> { "index=\"0\"" };
        if (cue.Name.Length > 0)
        {
            attributes.Add($"name=\"{Escape(cue.Name)}\"");
        }

        if (cue.FadeTime.FadeIn > 0)
        {
            attributes.Add($"basic_fade=\"{FadeTimeFormatting.FormatNumber(cue.FadeTime.FadeIn)}\"");
        }

        if (cue.FadeTime.FadeOut > 0)
        {
            attributes.Add($"basic_outfade=\"{FadeTimeFormatting.FormatNumber(cue.FadeTime.FadeOut)}\"");
        }

        return $"<CuePart {string.Join(' ', attributes)} />";
    }
}
