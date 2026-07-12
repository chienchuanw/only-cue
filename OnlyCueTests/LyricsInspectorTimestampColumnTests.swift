import AppKit
import XCTest
@testable import OnlyCue

/// Regression guard for issue #615. The placed-row timestamp column in the
/// lyric inspector was a hard-coded 62pt, but `LyricsTimeFormat.clockString`
/// renders 10 glyphs ("00:00:00.0") which measure ~66pt in the DS 11pt
/// monospaced font — so every timestamp wrapped onto a second line (Figma
/// 318:1490 shows a single-line timestamp). The fix routes the width through
/// `LyricsInspectorMetrics.timestampColumnWidth`, sized to fit the rendered
/// string; these tests pin both the seam and the fits-on-one-line invariant.
final class LyricsInspectorTimestampColumnTests: XCTestCase {

    /// The widest string the clock format produces below 10 hours — every
    /// glyph slot occupied. Monospaced font ⇒ any other sub-10h timestamp is
    /// the same width or narrower.
    private let widestTimestamp = LyricsTimeFormat.clockString(9 * 3600 + 59 * 60 + 59.9)

    /// AppKit twin of `DS.Text.monoSmall` (`Font.system(size: 11, design:
    /// .monospaced)`) — same size, same design, measurable via NSAttributedString.
    private let monoSmall = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)

    func test_clockString_widestForm_isTenGlyphs() {
        XCTAssertEqual(widestTimestamp, "09:59:59.9")
        XCTAssertEqual(widestTimestamp.count, 10)
    }

    func test_timestampColumn_fitsRenderedClockString() {
        let rendered = (widestTimestamp as NSString)
            .size(withAttributes: [.font: monoSmall])
            .width
        XCTAssertGreaterThanOrEqual(
            LyricsInspectorMetrics.timestampColumnWidth,
            ceil(rendered),
            "timestamp column (\(LyricsInspectorMetrics.timestampColumnWidth)pt) is narrower than "
                + "the rendered clock string (\(rendered)pt) — the timestamp wraps to two lines (#615)"
        )
    }
}
