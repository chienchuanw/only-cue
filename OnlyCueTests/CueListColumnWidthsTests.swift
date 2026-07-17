import XCTest
@testable import OnlyCue

final class CueListColumnWidthsTests: XCTestCase {

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
        XCTAssertTrue(CueListColumnWidths.numberRange.contains(CueListColumnWidths.numberDefault))
        XCTAssertTrue(CueListColumnWidths.infoRange.contains(CueListColumnWidths.infoDefault))
    }

    func test_storageKeys_areNonEmpty_andDistinct() {
        XCTAssertFalse(CueListColumnWidths.numberStorageKey.isEmpty)
        XCTAssertFalse(CueListColumnWidths.infoStorageKey.isEmpty)
        XCTAssertNotEqual(CueListColumnWidths.numberStorageKey, CueListColumnWidths.infoStorageKey)
    }

    // MARK: - Info column (#661)

    func test_clampInfo_belowMin_returnsLowerBound() {
        XCTAssertEqual(CueListColumnWidths.clampInfo(0), CueListColumnWidths.infoRange.lowerBound)
    }

    func test_clampInfo_aboveMax_returnsUpperBound() {
        XCTAssertEqual(CueListColumnWidths.clampInfo(9_999), CueListColumnWidths.infoRange.upperBound)
    }

    func test_clampInfo_inRange_returnsValue() {
        let mid = (CueListColumnWidths.infoRange.lowerBound + CueListColumnWidths.infoRange.upperBound) / 2
        XCTAssertEqual(CueListColumnWidths.clampInfo(mid), mid)
    }
}
