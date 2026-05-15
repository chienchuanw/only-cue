import XCTest
@testable import OnlyCue

final class CueListColumnWidthsTests: XCTestCase {

    func test_clampTime_belowMin_returnsLowerBound() {
        XCTAssertEqual(CueListColumnWidths.clampTime(0), CueListColumnWidths.timeRange.lowerBound)
        XCTAssertEqual(CueListColumnWidths.clampTime(-50), CueListColumnWidths.timeRange.lowerBound)
    }

    func test_clampTime_aboveMax_returnsUpperBound() {
        XCTAssertEqual(CueListColumnWidths.clampTime(9999), CueListColumnWidths.timeRange.upperBound)
    }

    func test_clampTime_inRange_returnsValue() {
        XCTAssertEqual(CueListColumnWidths.clampTime(120), 120)
    }

    func test_clampNumber_belowMin_returnsLowerBound() {
        XCTAssertEqual(CueListColumnWidths.clampNumber(0), CueListColumnWidths.numberRange.lowerBound)
    }

    func test_clampNumber_aboveMax_returnsUpperBound() {
        XCTAssertEqual(CueListColumnWidths.clampNumber(9999), CueListColumnWidths.numberRange.upperBound)
    }

    func test_clampNumber_inRange_returnsValue() {
        XCTAssertEqual(CueListColumnWidths.clampNumber(80), 80)
    }

    func test_defaults_areInsideRanges() {
        XCTAssertTrue(CueListColumnWidths.timeRange.contains(CueListColumnWidths.timeDefault))
        XCTAssertTrue(CueListColumnWidths.numberRange.contains(CueListColumnWidths.numberDefault))
    }

    func test_storageKeys_areNonEmpty_andDistinct() {
        XCTAssertFalse(CueListColumnWidths.timeStorageKey.isEmpty)
        XCTAssertFalse(CueListColumnWidths.numberStorageKey.isEmpty)
        XCTAssertNotEqual(CueListColumnWidths.timeStorageKey, CueListColumnWidths.numberStorageKey)
    }

    // MARK: - Fade column (#291)

    func test_clampFade_belowMin_returnsLowerBound() {
        XCTAssertEqual(CueListColumnWidths.clampFade(0), CueListColumnWidths.fadeRange.lowerBound)
    }

    func test_clampFade_aboveMax_returnsUpperBound() {
        XCTAssertEqual(CueListColumnWidths.clampFade(9_999), CueListColumnWidths.fadeRange.upperBound)
    }

    func test_clampFade_inRange_returnsValue() {
        let mid = (CueListColumnWidths.fadeRange.lowerBound + CueListColumnWidths.fadeRange.upperBound) / 2
        XCTAssertEqual(CueListColumnWidths.clampFade(mid), mid)
    }

    func test_fadeDefault_isInsideFadeRange() {
        XCTAssertTrue(CueListColumnWidths.fadeRange.contains(CueListColumnWidths.fadeDefault))
    }

    func test_fadeStorageKey_isNonEmpty_andDistinct() {
        XCTAssertFalse(CueListColumnWidths.fadeStorageKey.isEmpty)
        XCTAssertNotEqual(CueListColumnWidths.fadeStorageKey, CueListColumnWidths.timeStorageKey)
        XCTAssertNotEqual(CueListColumnWidths.fadeStorageKey, CueListColumnWidths.numberStorageKey)
    }
}
