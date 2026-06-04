import XCTest
import SwiftUI
import AppKit
@testable import OnlyCue

/// Pins the Lyrics inspector header (#413, Figma `318:1469`): an uppercase
/// `LYRICS` caption + a pluralised `{N} lines` total-count badge, matching the
/// `CueListSectionHeader` treatment. The count is the total of placed +
/// unplaced lines.
final class LyricsInspectorHeaderTests: XCTestCase {

    func test_lineCountText_zero_isPluralised() {
        XCTAssertEqual(LyricsInspectorPane.lineCountText(for: 0), "0 lines")
    }

    func test_lineCountText_one_isSingular() {
        XCTAssertEqual(LyricsInspectorPane.lineCountText(for: 1), "1 line")
    }

    func test_lineCountText_many_isPluralised() {
        XCTAssertEqual(LyricsInspectorPane.lineCountText(for: 12), "12 lines")
    }
}
