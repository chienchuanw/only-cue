import XCTest
@testable import OnlyCue

/// #569 — the export save-panel should suggest "abc.csv" for "abc.mp3", not
/// "abc.mp3.csv".
final class CueExportFilenameTests: XCTestCase {

    func test_stripsMediaExtension() {
        XCTAssertEqual(CueCSVExportAction.suggestedFilename(forItemName: "abc.mp3", target: .csv), "abc.csv")
        XCTAssertEqual(CueCSVExportAction.suggestedFilename(forItemName: "Opening.wav", target: .tsv), "Opening.tsv")
    }

    func test_noExtension_appendsTargetExtension() {
        // e.g. an alternate name with no extension.
        XCTAssertEqual(CueCSVExportAction.suggestedFilename(forItemName: "Opening Cue", target: .csv), "Opening Cue.csv")
    }

    func test_grandMA_usesCsvExtension() {
        XCTAssertEqual(CueCSVExportAction.suggestedFilename(forItemName: "set.mov", target: .ma3), "set.csv")
    }

    func test_onlyLastExtensionStripped() {
        XCTAssertEqual(CueCSVExportAction.suggestedFilename(forItemName: "track.final.mp3", target: .csv), "track.final.csv")
    }
}
