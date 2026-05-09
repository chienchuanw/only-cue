import XCTest
@testable import OnlyCue

@MainActor
final class FirstResponderResignTests: XCTestCase {

    func test_clickInsideTextFieldFrame_doesNotResign() {
        let frame = NSRect(x: 10, y: 10, width: 100, height: 30)
        let click = NSPoint(x: 50, y: 25)
        XCTAssertFalse(
            FirstResponderResign.shouldResign(
                clickLocationInWindow: click,
                firstResponderFrameInWindow: frame,
                firstResponderIsText: true
            ),
            "click inside the active text field's frame must not resign — lets the user move the cursor"
        )
    }

    func test_clickOutsideTextFieldFrame_resigns() {
        let frame = NSRect(x: 10, y: 10, width: 100, height: 30)
        let click = NSPoint(x: 200, y: 200)
        XCTAssertTrue(
            FirstResponderResign.shouldResign(
                clickLocationInWindow: click,
                firstResponderFrameInWindow: frame,
                firstResponderIsText: true
            )
        )
    }

    func test_clickWhenFirstResponderIsNotText_doesNotResign() {
        let frame = NSRect(x: 10, y: 10, width: 100, height: 30)
        let click = NSPoint(x: 200, y: 200)
        XCTAssertFalse(
            FirstResponderResign.shouldResign(
                clickLocationInWindow: click,
                firstResponderFrameInWindow: frame,
                firstResponderIsText: false
            ),
            "we must not yank focus from buttons / segmented controls / other non-text first responders"
        )
    }

    func test_clickOnFirstResponderEdge_doesNotResign() {
        let frame = NSRect(x: 10, y: 10, width: 100, height: 30)
        let click = NSPoint(x: 10, y: 10)
        XCTAssertFalse(
            FirstResponderResign.shouldResign(
                clickLocationInWindow: click,
                firstResponderFrameInWindow: frame,
                firstResponderIsText: true
            ),
            "boundary case — NSRect.contains is inclusive, so a click on the top-left corner is inside"
        )
    }
}
