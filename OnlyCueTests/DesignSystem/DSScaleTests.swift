import XCTest
@testable import OnlyCue

final class DSScaleTests: XCTestCase {

    func testSpacingGridIsAscendingMultiplesOfFour() {
        let scale = [DS.Space.xs, DS.Space.sm, DS.Space.md,
                     DS.Space.lg, DS.Space.xl, DS.Space.xxl]
        XCTAssertEqual(scale, [4, 8, 12, 16, 24, 32])
        for value in scale {
            XCTAssertEqual(value.truncatingRemainder(dividingBy: 4), 0)
        }
    }

    func testRadiiAreAscending() {
        XCTAssertLessThan(DS.Radius.sm, DS.Radius.md)
        XCTAssertLessThan(DS.Radius.md, DS.Radius.lg)
    }
}
