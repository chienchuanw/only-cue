import XCTest
import SwiftUI
@testable import OnlyCue

final class ItemRowFillTests: XCTestCase {

    private let selection = Color.gray

    /// The active sidebar row carries the selection-pill fill.
    func test_activeRow_usesSelectionFill() {
        XCTAssertEqual(ItemRowFill.color(isActive: true, selection: selection), selection)
    }

    /// Non-active rows are clean (Figma 318:1238).
    func test_inactiveRow_isClear() {
        XCTAssertEqual(ItemRowFill.color(isActive: false, selection: selection), .clear)
    }
}
