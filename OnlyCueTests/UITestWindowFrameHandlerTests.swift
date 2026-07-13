#if DEBUG
import XCTest
import AppKit
@testable import OnlyCue

/// Unit tests for the pure parsing seam of the screenshot window-frame handler
/// (#614). The handler pins the document window to a deterministic frame so
/// `XCUIElement.screenshot()` captures the full inspector regardless of the
/// capture display's size/orientation — the parse is isolated here so the
/// `WxH` grammar is testable without launching the app.
final class UITestWindowFrameHandlerTests: XCTestCase {

    func test_windowSize_validArgument_parsesWidthAndHeight() {
        let size = UITestWindowFrameHandler.windowSize(
            from: ["OnlyCue", "--ui-test-window=1280x820"]
        )
        XCTAssertEqual(size, CGSize(width: 1280, height: 820))
    }

    func test_windowSize_absentArgument_isNil() {
        let size = UITestWindowFrameHandler.windowSize(
            from: ["OnlyCue", "--ui-test-appearance=dark"]
        )
        XCTAssertNil(size)
    }

    func test_windowSize_malformedValue_isNil() {
        // Missing the height half, non-numeric, and zero/negative are all
        // rejected so a typo fails loudly instead of pinning a garbage frame.
        XCTAssertNil(UITestWindowFrameHandler.windowSize(from: ["OnlyCue", "--ui-test-window=1280"]))
        XCTAssertNil(UITestWindowFrameHandler.windowSize(from: ["OnlyCue", "--ui-test-window=wide"]))
        XCTAssertNil(UITestWindowFrameHandler.windowSize(from: ["OnlyCue", "--ui-test-window=1280x0"]))
        XCTAssertNil(UITestWindowFrameHandler.windowSize(from: ["OnlyCue", "--ui-test-window=-1280x820"]))
    }
}
#endif
