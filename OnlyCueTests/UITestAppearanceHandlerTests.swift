#if DEBUG
import XCTest
import AppKit
@testable import OnlyCue

final class UITestAppearanceHandlerTests: XCTestCase {

    func test_appearanceName_darkArgument_resolvesToDarkAqua() {
        let name = UITestAppearanceHandler.appearanceName(
            from: ["OnlyCue", "--ui-test-appearance=dark"]
        )
        XCTAssertEqual(name, .darkAqua)
    }

    func test_appearanceName_lightArgument_resolvesToAqua() {
        let name = UITestAppearanceHandler.appearanceName(
            from: ["OnlyCue", "--ui-test-appearance=light"]
        )
        XCTAssertEqual(name, .aqua)
    }

    func test_appearanceName_absentArgument_isNil() {
        let name = UITestAppearanceHandler.appearanceName(
            from: ["OnlyCue", "--ui-test-seed=three-cues-1-3-6"]
        )
        XCTAssertNil(name)
    }

    func test_appearanceName_unrecognizedValue_isNil() {
        let name = UITestAppearanceHandler.appearanceName(
            from: ["OnlyCue", "--ui-test-appearance=sepia"]
        )
        XCTAssertNil(name)
    }
}
#endif
