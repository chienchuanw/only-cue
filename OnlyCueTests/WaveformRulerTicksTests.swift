import XCTest
@testable import OnlyCue

/// `WaveformRulerTicks` — the mm:ss time-ruler above the waveform (#467, Figma
/// `318:1271`). Pure tick math: evenly-spaced positions across the content
/// width, zero-padded `MM:SS` (or `H:MM:SS`) labels, every fifth tick major.
final class WaveformRulerTicksTests: XCTestCase {

    func test_emptyForNonPositiveDurationOrWidth() {
        XCTAssertTrue(WaveformRulerTicks.ticks(duration: 0, contentWidth: 100).isEmpty)
        XCTAssertTrue(WaveformRulerTicks.ticks(duration: 60, contentWidth: 0).isEmpty)
    }

    func test_positionsSpanTheContentWidth() {
        // 120 s across 1200 pt → 10 pt/s. At this density the picked bucket is
        // 15 s (>= 56 pt/label), so ticks land at 0, 150, 300, ... pt.
        let ticks = WaveformRulerTicks.ticks(duration: 120, contentWidth: 1200)
        XCTAssertEqual(ticks.first?.x, 0)
        XCTAssertEqual(ticks.map(\.x).first(where: { $0 == 150 }), 150)
        // No tick is placed beyond the content width.
        XCTAssertTrue(ticks.allSatisfy { $0.x <= 1200 + 0.001 })
    }

    func test_labels_areZeroPaddedMinutesSeconds_underAnHour() {
        // 1 pt/s over 180 s → coarse 60 s bucket → labels at 0/60/120/180 s.
        let labels = WaveformRulerTicks.ticks(duration: 180, contentWidth: 180).map(\.label)
        XCTAssertEqual(labels, ["00:00", "01:00", "02:00", "03:00"])
    }

    func test_labels_showHoursPastAnHour() {
        let ticks = WaveformRulerTicks.ticks(duration: 7200, contentWidth: 7200)
        XCTAssertEqual(ticks.first?.label, "00:00")
        XCTAssertEqual(ticks.last(where: { $0.label == "1:00:00" })?.label, "1:00:00")
    }

    func test_everyFifthTickIsMajor() {
        let ticks = WaveformRulerTicks.ticks(duration: 60, contentWidth: 6000) // 100 pt/s → 1 s bucket
        XCTAssertEqual(ticks[0].isMajor, true)
        XCTAssertEqual(ticks[1].isMajor, false)
        XCTAssertEqual(ticks[5].isMajor, true)
    }
}
