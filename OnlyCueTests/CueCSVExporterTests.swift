import XCTest
@testable import OnlyCue

/// Pins the CSV export schema (RFC 4180 quoting + decimal-second times).
/// Header is fixed; column order is the contract for grandMA / generic-CSV
/// downstream consumers.
final class CueCSVExporterTests: XCTestCase {

    func test_emptyList_returnsHeaderOnly() {
        let csv = CueCSVExporter.csv(cues: [], typeNamesByID: [:])
        XCTAssertEqual(csv, "id,name,time,fadeIn,fadeOut,type,notes\n")
    }

    func test_singleCue_writesAllFields() throws {
        let typeID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let cueID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let cue = Cue(
            id: cueID,
            typeID: typeID,
            cueNumber: 1,
            name: "Bridge Hit",
            time: 12.5,
            notes: "key change",
            fadeTime: FadeTime(fadeIn: 0.5, fadeOut: 1.25)
        )
        let csv = CueCSVExporter.csv(
            cues: [cue],
            typeNamesByID: [typeID: "Lighting"]
        )
        XCTAssertEqual(csv, """
        id,name,time,fadeIn,fadeOut,type,notes
        00000000-0000-0000-0000-000000000002,Bridge Hit,12.5,0.5,1.25,Lighting,key change

        """)
    }

    func test_specialCharacters_areEscapedPerRFC4180() throws {
        // Comma → quote-wrap. Quote → double the quote AND wrap. Newline → quote-wrap.
        let cue = Cue(
            id: try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000003")),
            typeID: try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000004")),
            cueNumber: 2,
            name: #"He said, "go""#,
            time: 5.0,
            notes: "line 1\nline 2",
            fadeTime: FadeTime(fadeIn: 0, fadeOut: 0)
        )
        let csv = CueCSVExporter.csv(
            cues: [cue],
            typeNamesByID: [cue.typeID: "Sound, FX"]
        )
        // name: contains quote AND comma — wrapped + quotes doubled
        // type: contains comma — wrapped
        // notes: contains newline — wrapped
        XCTAssertTrue(csv.contains(#""He said, ""go""""#))
        XCTAssertTrue(csv.contains(#""Sound, FX""#))
        XCTAssertTrue(csv.contains("\"line 1\nline 2\""))
    }

    func test_unknownTypeID_writesEmptyTypeColumn() {
        let cue = Cue(
            id: UUID(),
            typeID: UUID(),
            cueNumber: 1,
            name: "x",
            time: 0,
            notes: "",
            fadeTime: .zero
        )
        let csv = CueCSVExporter.csv(cues: [cue], typeNamesByID: [:])
        // Type column is empty (two consecutive commas around it).
        XCTAssertTrue(csv.contains(",,"), "Expected empty type column (consecutive commas), got: \(csv)")
    }

    func test_multipleCues_oneRowEach_inInputOrder() {
        let cue1 = makeCue(time: 1.0, name: "first")
        let cue2 = makeCue(time: 2.0, name: "second")
        let csv = CueCSVExporter.csv(cues: [cue1, cue2], typeNamesByID: [:])
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: false)
        XCTAssertEqual(lines.count, 4) // header + 2 rows + trailing empty
        XCTAssertTrue(lines[1].contains("first"))
        XCTAssertTrue(lines[2].contains("second"))
    }

    private func makeCue(time: TimeInterval, name: String) -> Cue {
        Cue(
            id: UUID(),
            typeID: UUID(),
            cueNumber: 1,
            name: name,
            time: time,
            notes: "",
            fadeTime: .zero
        )
    }
}
