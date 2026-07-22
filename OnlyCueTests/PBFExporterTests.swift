import XCTest
@testable import OnlyCue

/// Pins the PotPlayer `.pbf` bookmark format: `[Bookmark]` header, 1-based
/// `index=ms*title*` lines, time-sorted, `[Type] Number Name` titles, and
/// title sanitization of the `*`/CR/LF format characters.
final class PBFExporterTests: XCTestCase {

    private func cue(
        type: UUID = UUID(),
        number: Double? = nil,
        name: String = "",
        time: TimeInterval
    ) -> Cue {
        Cue(id: UUID(), typeID: type, cueNumber: number, name: name,
            time: time, notes: "", fadeTime: FadeTime(fadeIn: 0, fadeOut: 0))
    }

    func test_emptyList_returnsHeaderOnly() {
        XCTAssertEqual(PBFExporter.pbf(cues: [], typeNamesByID: [:]), "[Bookmark]\n")
    }

    func test_singleCue_formatsTypeNumberName() {
        let type = UUID()
        let out = PBFExporter.pbf(
            cues: [cue(type: type, number: 12, name: "副歌", time: 12.5)],
            typeNamesByID: [type: "Lighting"]
        )
        XCTAssertEqual(out, "[Bookmark]\n1=12500*[Lighting] 12 副歌*\n")
    }

    func test_time_isRoundedToNearestMillisecond() {
        let out = PBFExporter.pbf(cues: [cue(name: "x", time: 3.4567)], typeNamesByID: [:])
        XCTAssertTrue(out.contains("=3457*"), out)
    }

    func test_cuesAreSortedByTime_withOneBasedIndex() {
        let out = PBFExporter.pbf(
            cues: [cue(name: "late", time: 9), cue(name: "early", time: 1)],
            typeNamesByID: [:]
        )
        XCTAssertEqual(out, "[Bookmark]\n1=1000*early*\n2=9000*late*\n")
    }

    func test_unnumberedCue_dropsNumber() {
        let type = UUID()
        let out = PBFExporter.pbf(cues: [cue(type: type, name: "副歌", time: 0)],
                                  typeNamesByID: [type: "Lighting"])
        XCTAssertEqual(out, "[Bookmark]\n1=0*[Lighting] 副歌*\n")
    }

    func test_unknownType_dropsBracket() {
        let out = PBFExporter.pbf(cues: [cue(number: 3, name: "hit", time: 0)],
                                  typeNamesByID: [:])
        XCTAssertEqual(out, "[Bookmark]\n1=0*3 hit*\n")
    }

    func test_titleSanitizesDelimiterAndNewlines() {
        let type = UUID()
        let out = PBFExporter.pbf(
            cues: [cue(type: type, number: 5, name: "hit*flash\nbig", time: 0)],
            typeNamesByID: [type: "FX"]
        )
        XCTAssertEqual(out, "[Bookmark]\n1=0*[FX] 5 hit flash big*\n")
    }
}
