import XCTest
@testable import OnlyCue

final class EditorModeTests: XCTestCase {

    func test_allCases_areCueLyricShow() {
        XCTAssertEqual(EditorMode.allCases, [.cue, .lyric, .show])
    }

    func test_rawValuesAreStable() {
        // Raw values are persisted in @SceneStorage — they must not drift.
        XCTAssertEqual(EditorMode.cue.rawValue, "cue")
        XCTAssertEqual(EditorMode.lyric.rawValue, "lyric")
        XCTAssertEqual(EditorMode.show.rawValue, "show")
    }

    func test_titleIsHumanReadable() {
        XCTAssertEqual(EditorMode.cue.title, "Cue")
        XCTAssertEqual(EditorMode.lyric.title, "Lyric")
        XCTAssertEqual(EditorMode.show.title, "Show")
    }

    func test_cueMarkersEditable_onlyInCueMode() {
        XCTAssertTrue(EditorMode.cue.cueMarkersEditable)
        XCTAssertFalse(EditorMode.lyric.cueMarkersEditable)
        XCTAssertFalse(EditorMode.show.cueMarkersEditable)
    }

    func test_lyricsEditable_onlyInLyricMode() {
        XCTAssertFalse(EditorMode.cue.lyricsEditable)
        XCTAssertTrue(EditorMode.lyric.lyricsEditable)
        XCTAssertFalse(EditorMode.show.lyricsEditable)
    }

    func test_isReadOnly_onlyInShowMode() {
        XCTAssertFalse(EditorMode.cue.isReadOnly)
        XCTAssertFalse(EditorMode.lyric.isReadOnly)
        XCTAssertTrue(EditorMode.show.isReadOnly)
    }
}
