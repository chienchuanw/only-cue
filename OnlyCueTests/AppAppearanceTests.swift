import XCTest
import AppKit
@testable import OnlyCue

final class AppAppearanceTests: XCTestCase {

    /// Dark-only main window (ADR-029): the single shipped appearance is Dark
    /// Aqua, so system-drawn chrome matches the dark Figma design system.
    func test_productionAppearance_isDarkAqua() {
        XCTAssertEqual(AppAppearance.production, .darkAqua)
    }
}
