import XCTest
@testable import OnlyCue

/// #683 — the sequence import XML pushed to grandMA2. Structure researched from
/// real console exports (spec `## XML schemas`): `Sequ → Cue → Number +
/// CuePart(name, basic_fade, basic_outfade) + InfoItems/Info`, cue-only (no
/// CueDatas). `sub_number` is thousandths (3.5 → 500) — flagged for real-rig
/// verification in the plan.
final class MA2SequenceXMLGeneratorTests: XCTestCase {

    private func cue(
        number: Double,
        name: String = "",
        time: TimeInterval = 0,
        notes: String = "",
        fadeIn: TimeInterval = 0,
        fadeOut: TimeInterval = 0
    ) -> Cue {
        Cue(
            id: UUID(),
            typeID: UUID(),
            cueNumber: number,
            name: name,
            time: time,
            notes: notes,
            fadeTime: FadeTime(fadeIn: fadeIn, fadeOut: fadeOut)
        )
    }

    func test_cueNumberComponents_thousandths() {
        XCTAssertEqual(MA2CueNumber.components(from: 3), .init(number: 3, subNumber: 0))
        XCTAssertEqual(MA2CueNumber.components(from: 3.5), .init(number: 3, subNumber: 500))
        XCTAssertEqual(MA2CueNumber.components(from: 3.15), .init(number: 3, subNumber: 150))
        XCTAssertEqual(MA2CueNumber.components(from: 3.001), .init(number: 3, subNumber: 1))
        // Float noise must not leak (0.1 + 0.2 style): 1.3 is exactly sub 300.
        XCTAssertEqual(MA2CueNumber.components(from: 1.3), .init(number: 1, subNumber: 300))
    }

    func test_fullDocument_goldenSkeleton() {
        let cues = [
            cue(number: 1, name: "Intro", notes: "house out", fadeIn: 2.5),
            cue(number: 2.5, name: "A <b> & \"q\"", fadeIn: 1, fadeOut: 3)
        ]
        let xml = MA2SequenceXMLGenerator.xml(
            cues: cues,
            sequenceName: "Opening",
            showfile: "MyShow",
            datetime: "2026-07-19T12:00:00"
        )
        let expected = """
        <?xml version="1.0" encoding="utf-8"?>
        <?xml-stylesheet type="text/xsl" href="styles/sequ@html@default.xsl"?>
        <MA xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns="http://schemas.malighting.de/grandma2/xml/MA" xsi:schemaLocation="http://schemas.malighting.de/grandma2/xml/MA http://schemas.malighting.de/grandma2/xml/3.9.60/MA.xsd" major_vers="3" minor_vers="9" stream_vers="60">
        \t<Info datetime="2026-07-19T12:00:00" showfile="MyShow" />
        \t<Sequ index="0" name="Opening" timecode_slot="255" forced_position_mode="0">
        \t\t<Cue xsi:nil="true" />
        \t\t<Cue index="1">
        \t\t\t<Number number="1" sub_number="0" />
        \t\t\t<CuePart index="0" name="Intro" basic_fade="2.5" />
        \t\t\t<InfoItems>
        \t\t\t\t<Info>house out</Info>
        \t\t\t</InfoItems>
        \t\t</Cue>
        \t\t<Cue index="2">
        \t\t\t<Number number="2" sub_number="500" />
        \t\t\t<CuePart index="0" name="A &lt;b&gt; &amp; &quot;q&quot;" basic_fade="1" basic_outfade="3" />
        \t\t</Cue>
        \t</Sequ>
        </MA>
        """
        XCTAssertEqual(xml, expected)
    }

    func test_cuesAreOrderedByNumber_notByTime() throws {
        // OnlyCue cue numbers need not be monotonic with time; MA2 sequences
        // are number-ordered, and the timecode generator references cues by
        // this number-sorted index.
        let cues = [
            cue(number: 2, name: "Second", time: 1),
            cue(number: 1, name: "First", time: 5)
        ]
        let xml = MA2SequenceXMLGenerator.xml(
            cues: cues, sequenceName: "S", showfile: "F", datetime: "2026-07-19T12:00:00"
        )
        let first = try XCTUnwrap(xml.range(of: "name=\"First\""))
        let second = try XCTUnwrap(xml.range(of: "name=\"Second\""))
        XCTAssertTrue(first.lowerBound < second.lowerBound)
    }

    func test_zeroFades_omitted_emptyNotes_omitInfoItems() {
        let xml = MA2SequenceXMLGenerator.xml(
            cues: [cue(number: 7)], sequenceName: "S", showfile: "F", datetime: "2026-07-19T12:00:00"
        )
        XCTAssertTrue(xml.contains("<CuePart index=\"0\" />"))
        XCTAssertFalse(xml.contains("basic_fade"))
        XCTAssertFalse(xml.contains("InfoItems"))
    }
}
