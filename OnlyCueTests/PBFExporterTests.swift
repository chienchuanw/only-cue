import XCTest
@testable import OnlyCue

/// Pins the PotPlayer `.pbf` bookmark body (the logical text; the writer adds
/// the UTF-16LE BOM). Format matches a real PotPlayer-authored file: `[Bookmark]`
/// header, **0-based** `index=ms*title*` lines, **CRLF** terminators, a trailing
/// `{count}=` next-index slot, a final blank line, and `[Type] Number Name`
/// titles with `*`/CR/LF sanitized.
final class PBFExporterTests: XCTestCase {

    private func cue(
        type: UUID = UUID(),
        number: Double? = nil,
        name: String = "",
        time: TimeInterval
    ) -> Cue {
        Cue(
            id: UUID(),
            typeID: type,
            cueNumber: number,
            name: name,
            time: time,
            notes: "",
            fadeTime: FadeTime(fadeIn: 0, fadeOut: 0)
        )
    }

    func test_emptyList_returnsHeaderAndTrailingSlot() {
        XCTAssertEqual(PBFExporter.pbf(cues: [], typeNamesByID: [:]), "[Bookmark]\r\n0=\r\n\r\n")
    }

    func test_singleCue_formatsTypeNumberName() {
        let type = UUID()
        let out = PBFExporter.pbf(
            cues: [cue(type: type, number: 12, name: "副歌", time: 12.5)],
            typeNamesByID: [type: "Lighting"]
        )
        XCTAssertEqual(out, "[Bookmark]\r\n0=12500*[Lighting] 12 副歌*\r\n1=\r\n\r\n")
    }

    func test_time_isRoundedToNearestMillisecond() {
        let out = PBFExporter.pbf(cues: [cue(name: "x", time: 3.4567)], typeNamesByID: [:])
        XCTAssertTrue(out.contains("0=3457*"), out)
    }

    func test_cuesAreSortedByTime_withZeroBasedIndex() {
        let out = PBFExporter.pbf(
            cues: [cue(name: "late", time: 9), cue(name: "early", time: 1)],
            typeNamesByID: [:]
        )
        XCTAssertEqual(out, "[Bookmark]\r\n0=1000*early*\r\n1=9000*late*\r\n2=\r\n\r\n")
    }

    func test_sameMillisecond_ordersByCueNumber() {
        let type = UUID()
        let out = PBFExporter.pbf(
            cues: [
                cue(type: type, number: 2, name: "b", time: 4),
                cue(type: type, number: 1, name: "a", time: 4)
            ],
            typeNamesByID: [type: "L"]
        )
        XCTAssertEqual(out, "[Bookmark]\r\n0=4000*[L] 1 a*\r\n1=4000*[L] 2 b*\r\n2=\r\n\r\n")
    }

    func test_unnumberedCue_dropsNumber() {
        let type = UUID()
        let out = PBFExporter.pbf(
            cues: [cue(type: type, name: "副歌", time: 0)],
            typeNamesByID: [type: "Lighting"]
        )
        XCTAssertEqual(out, "[Bookmark]\r\n0=0*[Lighting] 副歌*\r\n1=\r\n\r\n")
    }

    func test_unknownType_dropsBracket() {
        let out = PBFExporter.pbf(
            cues: [cue(number: 3, name: "hit", time: 0)],
            typeNamesByID: [:]
        )
        XCTAssertEqual(out, "[Bookmark]\r\n0=0*3 hit*\r\n1=\r\n\r\n")
    }

    func test_titleSanitizesDelimiterAndNewlines() {
        let type = UUID()
        let out = PBFExporter.pbf(
            cues: [cue(type: type, number: 5, name: "hit*flash\nbig", time: 0)],
            typeNamesByID: [type: "FX"]
        )
        XCTAssertEqual(out, "[Bookmark]\r\n0=0*[FX] 5 hit flash big*\r\n1=\r\n\r\n")
    }
}
