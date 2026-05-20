import XCTest
@testable import OnlyCue

/// Optional `LyricLine.time` (nil = unplaced) and the `Lyrics` normalization
/// change: `lines` keeps authoring order, `placedLines` / `unplacedLines` split it.
final class LyricsOptionalTimeTests: XCTestCase {

    private func placed(_ time: TimeInterval, _ text: String) -> LyricLine {
        LyricLine(time: time, text: text)
    }
    private func unplaced(_ text: String) -> LyricLine {
        LyricLine(time: nil, text: text)
    }

    // MARK: - LyricLine

    func test_lyricLine_nilTimeIsUnplaced() {
        XCTAssertNil(LyricLine(time: nil, text: "x").time)
    }

    func test_lyricLine_clampsNegativePlacedTime() {
        XCTAssertEqual(LyricLine(time: -3, text: "x").time, 0)
    }

    func test_lyricLine_codableRoundTrip_unplaced() throws {
        let original = LyricLine(id: UUID(), time: nil, text: "hello")
        let decoded = try JSONDecoder().decode(LyricLine.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded, original)
        XCTAssertNil(decoded.time)
    }

    func test_lyricLine_codableRoundTrip_placed() throws {
        let original = LyricLine(id: UUID(), time: 12.5, text: "hi")
        let decoded = try JSONDecoder().decode(LyricLine.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded, original)
    }

    func test_lyricLine_decodesLegacyPresentTime() throws {
        // A v13 doc always wrote a concrete `time` — it must still decode.
        let json = #"{"id":"\#(UUID().uuidString)","time":7.5,"text":"x"}"#
        let decoded = try JSONDecoder().decode(LyricLine.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.time, 7.5)
    }

    // MARK: - Lyrics normalization

    func test_lyrics_keepsLinesInAuthoringOrder() {
        let lyrics = Lyrics(lines: [placed(9, "c"), placed(1, "a"), placed(4, "b")], offsetSeconds: 0)
        XCTAssertEqual(lyrics.lines.map(\.text), ["c", "a", "b"], "lines is no longer sorted on init")
    }

    func test_placedLines_sortedByTime() {
        let lyrics = Lyrics(lines: [placed(9, "c"), unplaced("u"), placed(1, "a")], offsetSeconds: 0)
        XCTAssertEqual(lyrics.placedLines.map(\.text), ["a", "c"])
    }

    func test_unplacedLines_inAuthoringOrder() {
        let lyrics = Lyrics(lines: [unplaced("u1"), placed(1, "a"), unplaced("u2")], offsetSeconds: 0)
        XCTAssertEqual(lyrics.unplacedLines.map(\.text), ["u1", "u2"])
    }

    func test_lyrics_codableRoundTrip_preservesOrderAndOptionalTimes() throws {
        let lyrics = Lyrics(lines: [placed(5, "b"), unplaced("u"), placed(2, "a")], offsetSeconds: 60)
        let decoded = try JSONDecoder().decode(Lyrics.self, from: JSONEncoder().encode(lyrics))
        XCTAssertEqual(decoded.lines.map(\.text), ["b", "u", "a"])
        XCTAssertNil(decoded.lines[1].time)
        XCTAssertEqual(decoded.offsetSeconds, 60)
    }

    // MARK: - effectiveTime

    func test_effectiveTime_nilForUnplaced() {
        let lyrics = Lyrics(lines: [unplaced("u")], offsetSeconds: 10)
        XCTAssertNil(lyrics.effectiveTime(of: lyrics.lines[0]))
    }

    func test_effectiveTime_addsOffsetForPlaced() {
        let lyrics = Lyrics(lines: [placed(2, "a")], offsetSeconds: 60)
        XCTAssertEqual(lyrics.effectiveTime(of: lyrics.lines[0]), 62)
    }

    func test_effectiveTime_clampsToZero() {
        let lyrics = Lyrics(lines: [placed(1, "a")], offsetSeconds: -10)
        XCTAssertEqual(lyrics.effectiveTime(of: lyrics.lines[0]), 0)
    }

    // MARK: - activeLine / nextLine ignore unplaced lines

    func test_activeLine_ignoresUnplaced() {
        let lyrics = Lyrics(lines: [unplaced("u"), placed(5, "a"), placed(10, "b")], offsetSeconds: 0)
        XCTAssertEqual(lyrics.activeLine(atMediaSeconds: 7)?.text, "a")
        XCTAssertNil(lyrics.activeLine(atMediaSeconds: 4))
    }

    func test_activeLine_lastPlacedLinePersistsPastEnd() {
        let lyrics = Lyrics(lines: [placed(5, "a"), placed(10, "b")], offsetSeconds: 0)
        XCTAssertEqual(lyrics.activeLine(atMediaSeconds: 999)?.text, "b")
    }

    func test_nextLine_ignoresUnplaced() {
        let lyrics = Lyrics(lines: [placed(5, "a"), unplaced("u"), placed(10, "b")], offsetSeconds: 0)
        XCTAssertEqual(lyrics.nextLine(afterMediaSeconds: 7)?.text, "b")
    }

    func test_nextLine_nilPastLastPlacedLine() {
        let lyrics = Lyrics(lines: [placed(5, "a"), unplaced("u")], offsetSeconds: 0)
        XCTAssertNil(lyrics.nextLine(afterMediaSeconds: 6))
    }

    // MARK: - untimedLines now produce unplaced rows

    func test_untimedLines_produceUnplacedRows() {
        let lines = Lyrics.untimedLines(fromPlainText: "one\ntwo")
        XCTAssertEqual(lines.map(\.text), ["one", "two"])
        XCTAssertTrue(lines.allSatisfy { $0.time == nil }, "pasted lines start unplaced")
    }

    func test_untimedLines_handlesCarriageReturns() {
        let lines = Lyrics.untimedLines(fromPlainText: "a\r\nb")
        XCTAssertEqual(lines.map(\.text), ["a", "b"])
    }
}
