import XCTest
@testable import OnlyCue

final class LyricsTests: XCTestCase {

    private func line(_ time: TimeInterval, _ text: String) -> LyricLine {
        LyricLine(time: time, text: text)
    }

    // MARK: - LyricLine

    func test_lyricLine_clampsNegativeTimeToZero() {
        XCTAssertEqual(LyricLine(time: -3, text: "x").time, 0)
    }

    func test_lyricLine_codableRoundTrip() throws {
        let original = LyricLine(id: UUID(), time: 12.5, text: "hello")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(LyricLine.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func test_lyricLine_decodeRoutesThroughClampingInit() throws {
        let json = #"{"id":"\#(UUID().uuidString)","time":-9,"text":"x"}"#
        let decoded = try JSONDecoder().decode(LyricLine.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.time, 0, "a hand-edited negative time on disk is clamped on decode")
    }

    // MARK: - Lyrics normalization

    func test_lyrics_sortsLinesByTimeOnInit() {
        let lyrics = Lyrics(lines: [line(9, "c"), line(1, "a"), line(4, "b")], offsetSeconds: 0)
        XCTAssertEqual(lyrics.lines.map(\.text), ["a", "b", "c"])
    }

    func test_lyrics_codableRoundTripPreservesSortAndOffset() throws {
        let lyrics = Lyrics(lines: [line(5, "b"), line(2, "a")], offsetSeconds: 60)
        let data = try JSONEncoder().encode(lyrics)
        let decoded = try JSONDecoder().decode(Lyrics.self, from: data)
        XCTAssertEqual(decoded.lines.map(\.text), ["a", "b"])
        XCTAssertEqual(decoded.offsetSeconds, 60)
    }

    // MARK: - effectiveTime

    func test_effectiveTime_addsOffset() {
        let lyrics = Lyrics(lines: [line(2, "a")], offsetSeconds: 60)
        XCTAssertEqual(lyrics.effectiveTime(of: lyrics.lines[0]), 62)
    }

    func test_effectiveTime_clampsToZero() {
        let lyrics = Lyrics(lines: [line(1, "a")], offsetSeconds: -10)
        XCTAssertEqual(lyrics.effectiveTime(of: lyrics.lines[0]), 0)
    }

    // MARK: - activeLine

    func test_activeLine_nilBeforeFirstLine() {
        let lyrics = Lyrics(lines: [line(5, "a"), line(10, "b")], offsetSeconds: 0)
        XCTAssertNil(lyrics.activeLine(atMediaSeconds: 4))
    }

    func test_activeLine_returnsLineAtExactBoundary() {
        let lyrics = Lyrics(lines: [line(5, "a"), line(10, "b")], offsetSeconds: 0)
        XCTAssertEqual(lyrics.activeLine(atMediaSeconds: 5)?.text, "a")
    }

    func test_activeLine_returnsLatestLineAtOrBeforePlayhead() {
        let lyrics = Lyrics(lines: [line(5, "a"), line(10, "b")], offsetSeconds: 0)
        XCTAssertEqual(lyrics.activeLine(atMediaSeconds: 7)?.text, "a")
    }

    func test_activeLine_lastLinePersistsPastEnd() {
        let lyrics = Lyrics(lines: [line(5, "a"), line(10, "b")], offsetSeconds: 0)
        XCTAssertEqual(lyrics.activeLine(atMediaSeconds: 999)?.text, "b")
    }

    func test_activeLine_respectsOffset() {
        let lyrics = Lyrics(lines: [line(2, "a")], offsetSeconds: 60)
        XCTAssertNil(lyrics.activeLine(atMediaSeconds: 30), "line is at effective 62s")
        XCTAssertEqual(lyrics.activeLine(atMediaSeconds: 70)?.text, "a")
    }

    func test_activeLine_emptyLyrics_returnsNil() {
        XCTAssertNil(Lyrics.empty.activeLine(atMediaSeconds: 5))
    }

    // MARK: - nextLine

    func test_nextLine_returnsFollowingLine() {
        let lyrics = Lyrics(lines: [line(5, "a"), line(10, "b")], offsetSeconds: 0)
        XCTAssertEqual(lyrics.nextLine(afterMediaSeconds: 7)?.text, "b")
    }

    func test_nextLine_nilPastLastLine() {
        let lyrics = Lyrics(lines: [line(5, "a"), line(10, "b")], offsetSeconds: 0)
        XCTAssertNil(lyrics.nextLine(afterMediaSeconds: 12))
    }

    // MARK: - untimedLines

    func test_untimedLines_splitsOnNewlinesAllAtTimeZero() {
        let lines = Lyrics.untimedLines(fromPlainText: "one\ntwo\nthree")
        XCTAssertEqual(lines.map(\.text), ["one", "two", "three"])
        XCTAssertTrue(lines.allSatisfy { $0.time == 0 })
    }

    func test_untimedLines_preservesBlankLines() {
        let lines = Lyrics.untimedLines(fromPlainText: "verse\n\nchorus")
        XCTAssertEqual(lines.map(\.text), ["verse", "", "chorus"])
    }

    func test_untimedLines_handlesCarriageReturns() {
        let lines = Lyrics.untimedLines(fromPlainText: "a\r\nb")
        XCTAssertEqual(lines.map(\.text), ["a", "b"])
    }
}
