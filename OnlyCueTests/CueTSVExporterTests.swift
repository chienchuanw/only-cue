import XCTest
@testable import OnlyCue

/// Pins the TSV variant — same schema as CSV but tab-delimited. The escape
/// distinction matters: a value containing a comma must NOT be quoted in TSV
/// (commas are valid unescaped data in TSV), but the same value in CSV would
/// be wrapped. Tests both directions.
final class CueTSVExporterTests: XCTestCase {

    func test_tsv_emptyList_returnsTabDelimitedHeaderOnly() {
        let tsv = CueCSVExporter.tsv(cues: [], typeNamesByID: [:])
        XCTAssertEqual(tsv, "id\tname\ttime\tfadeIn\tfadeOut\ttype\tnotes\n")
    }

    func test_tsv_singleCue_usesTabsBetweenColumns() throws {
        let typeID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000010"))
        let cueID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000011"))
        let cue = Cue(
            id: cueID,
            typeID: typeID,
            cueNumber: 1,
            name: "Bridge",
            time: 1.0,
            notes: "",
            fadeTime: FadeTime(fadeIn: 0, fadeOut: 0)
        )
        let tsv = CueCSVExporter.tsv(cues: [cue], typeNamesByID: [typeID: "Lighting"])
        XCTAssertEqual(tsv, """
        id\tname\ttime\tfadeIn\tfadeOut\ttype\tnotes
        \(cueID.uuidString)\tBridge\t1.0\t0.0\t0.0\tLighting\t

        """)
    }

    func test_tsv_commaInValue_isNOTQuoted() {
        // Comma is plain data in TSV; only tab/quote/newline trigger quoting.
        let cue = Cue(
            id: UUID(),
            typeID: UUID(),
            cueNumber: 1,
            name: "Sound, FX",
            time: 0,
            notes: "",
            fadeTime: .zero
        )
        let tsv = CueCSVExporter.tsv(cues: [cue], typeNamesByID: [:])
        XCTAssertTrue(tsv.contains("Sound, FX"), "Comma should pass through unescaped in TSV")
        XCTAssertFalse(tsv.contains("\"Sound, FX\""), "TSV must not wrap comma-only values in quotes")
    }

    func test_tsv_tabInValue_IS_quoted() {
        let cue = Cue(
            id: UUID(),
            typeID: UUID(),
            cueNumber: 1,
            name: "tab\there",
            time: 0,
            notes: "",
            fadeTime: .zero
        )
        let tsv = CueCSVExporter.tsv(cues: [cue], typeNamesByID: [:])
        XCTAssertTrue(tsv.contains("\"tab\there\""), "TSV must quote-wrap values containing tabs")
    }

    func test_tsv_quoteInValue_IS_doubled_and_wrapped() {
        let cue = Cue(
            id: UUID(),
            typeID: UUID(),
            cueNumber: 1,
            name: "say \"hi\"",
            time: 0,
            notes: "",
            fadeTime: .zero
        )
        let tsv = CueCSVExporter.tsv(cues: [cue], typeNamesByID: [:])
        XCTAssertTrue(tsv.contains("\"say \"\"hi\"\"\""))
    }
}
