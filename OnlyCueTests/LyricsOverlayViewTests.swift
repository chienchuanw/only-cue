import XCTest
@testable import OnlyCue

/// `LyricsHUDContent` is the pure projection the HUD renders — it isolates the
/// "which two lines, and is the current one a gap" decision from SwiftUI.
final class LyricsOverlayViewTests: XCTestCase {

    private func lyrics(_ pairs: [(TimeInterval, String)], offset: TimeInterval = 0) -> Lyrics {
        Lyrics(lines: pairs.map { LyricLine(time: $0.0, text: $0.1) }, offsetSeconds: offset)
    }

    func test_content_nilBeforeFirstLine() {
        let content = LyricsHUDContent(lyrics: lyrics([(5, "a")]), mediaSeconds: 2)
        XCTAssertNil(content)
    }

    func test_content_currentAndNext() {
        let content = LyricsHUDContent(lyrics: lyrics([(5, "a"), (10, "b")]), mediaSeconds: 7)
        XCTAssertEqual(content?.currentText, "a")
        XCTAssertEqual(content?.nextText, "b")
    }

    func test_content_lastLineHasNoNext() {
        let content = LyricsHUDContent(lyrics: lyrics([(5, "a"), (10, "b")]), mediaSeconds: 12)
        XCTAssertEqual(content?.currentText, "b")
        XCTAssertNil(content?.nextText)
    }

    func test_content_emptyCurrentLineRendersAsGap() {
        let content = LyricsHUDContent(lyrics: lyrics([(5, "")]), mediaSeconds: 6)
        XCTAssertEqual(content?.currentText, "", "an instrumental-gap line renders a blank current line")
    }

    func test_content_nilWhenNoLyrics() {
        XCTAssertNil(LyricsHUDContent(lyrics: .empty, mediaSeconds: 5))
    }

    func test_content_respectsOffset() {
        let content = LyricsHUDContent(lyrics: lyrics([(2, "a")], offset: 60), mediaSeconds: 70)
        XCTAssertEqual(content?.currentText, "a", "line at effective 62s is active at 70s")
    }
}
