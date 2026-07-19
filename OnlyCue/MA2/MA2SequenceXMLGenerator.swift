import Foundation

/// Splits an OnlyCue `cueNumber` (Double) into grandMA2's `number` +
/// `sub_number` XML attributes. `sub_number` is **thousandths** (3.5 → 500):
/// MA2 cue numbers carry at most three decimals and thousandths are free of
/// the "3.15 vs 3.150" digit-string ambiguity. Isolated here so a real-rig
/// verification (#683 plan step 13) that contradicts the rule changes one
/// function.
enum MA2CueNumber {

    struct Components: Equatable {
        var number: Int
        var subNumber: Int
    }

    static func components(from value: Double) -> Components {
        // Round in integer thousandths so binary float noise (1.3 → 1300.0002)
        // cannot leak into the sub number.
        let thousandths = Int((value * 1000).rounded())
        return Components(number: thousandths / 1000, subNumber: thousandths % 1000)
    }

    /// Cue number as an MA2 command token: an integer when whole, else up to
    /// three decimals with trailing zeros trimmed (`1.15`, `2.001`, `3`). Used by
    /// the telnet command planner (#683, Approach A).
    static func commandString(from value: Double) -> String {
        let parts = components(from: value)
        guard parts.subNumber != 0 else { return "\(parts.number)" }
        var frac = String(format: "%03d", parts.subNumber)
        while frac.hasSuffix("0") { frac.removeLast() }
        return "\(parts.number).\(frac)"
    }
}

/// Generates the grandMA2 sequence import XML (#683): one content-empty cue
/// per OnlyCue cue with number, label, info and fades. Structure per the spec's
/// `## XML schemas` section (researched from real v3.9.x console exports);
/// cue-only imports (no `CueDatas`) are proven by TCHelper / MLA.
enum MA2SequenceXMLGenerator {

    static func xml(cues: [Cue], sequenceName: String, showfile: String, datetime: String) -> String {
        // MA2 sequences are number-ordered; the timecode generator references
        // cues by this number-sorted 1-based index. Cue numbers need not be
        // monotonic with cue times in OnlyCue.
        let ordered = cues.sorted { ($0.cueNumber ?? 0) < ($1.cueNumber ?? 0) }

        var lines: [String] = []
        lines.append("<?xml version=\"1.0\" encoding=\"utf-8\"?>")
        lines.append("<?xml-stylesheet type=\"text/xsl\" href=\"styles/sequ@html@default.xsl\"?>")
        lines.append(
            "<MA xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" "
            + "xmlns=\"http://schemas.malighting.de/grandma2/xml/MA\" "
            + "xsi:schemaLocation=\"http://schemas.malighting.de/grandma2/xml/MA "
            + "http://schemas.malighting.de/grandma2/xml/3.9.60/MA.xsd\" "
            + "major_vers=\"3\" minor_vers=\"9\" stream_vers=\"60\">"
        )
        lines.append("\t<Info datetime=\"\(escape(datetime))\" showfile=\"\(escape(showfile))\" />")
        lines.append(
            "\t<Sequ index=\"0\" name=\"\(escape(sequenceName))\" "
            + "timecode_slot=\"255\" forced_position_mode=\"0\">"
        )
        lines.append("\t\t<Cue xsi:nil=\"true\" />") // cue-zero placeholder
        for (position, cue) in ordered.enumerated() {
            lines.append(contentsOf: cueElement(cue, index: position + 1))
        }
        lines.append("\t</Sequ>")
        lines.append("</MA>")
        return lines.joined(separator: "\n")
    }

    private static func cueElement(_ cue: Cue, index: Int) -> [String] {
        let numberComponents = MA2CueNumber.components(from: cue.cueNumber ?? 0)
        var lines: [String] = []
        lines.append("\t\t<Cue index=\"\(index)\">")
        lines.append(
            "\t\t\t<Number number=\"\(numberComponents.number)\" "
            + "sub_number=\"\(numberComponents.subNumber)\" />"
        )
        lines.append("\t\t\t\(cuePart(cue))")
        if !cue.notes.isEmpty {
            lines.append("\t\t\t<InfoItems>")
            lines.append("\t\t\t\t<Info>\(escape(cue.notes))</Info>")
            lines.append("\t\t\t</InfoItems>")
        }
        lines.append("\t\t</Cue>")
        return lines
    }

    /// All cue data (name, fades) lives on part 0 in MA2. Zero fades and empty
    /// names are omitted — the import fills defaults.
    private static func cuePart(_ cue: Cue) -> String {
        var attributes = ["index=\"0\""]
        if !cue.name.isEmpty {
            attributes.append("name=\"\(escape(cue.name))\"")
        }
        if cue.fadeTime.fadeIn > 0 {
            attributes.append("basic_fade=\"\(FadeTime.formatNumber(cue.fadeTime.fadeIn))\"")
        }
        if cue.fadeTime.fadeOut > 0 {
            attributes.append("basic_outfade=\"\(FadeTime.formatNumber(cue.fadeTime.fadeOut))\"")
        }
        return "<CuePart \(attributes.joined(separator: " ")) />"
    }

    /// Minimal XML escaping for attribute values and text nodes.
    static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
