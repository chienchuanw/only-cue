import XCTest
@testable import OnlyCue

/// #575 — the cue inspector's top strip shows the active media item's filename.
/// `displayText(for:)` is the pure mapping from the optional resolved name to
/// the label string, with a stable placeholder when no media is loaded.
final class ActiveMediaNameHeaderTests: XCTestCase {

    func test_presentName_isShownVerbatim() {
        XCTAssertEqual(ActiveMediaNameHeader.displayText(for: "abc.mp3"), "abc.mp3")
    }

    func test_nilName_fallsBackToPlaceholder() {
        XCTAssertEqual(ActiveMediaNameHeader.displayText(for: nil), ActiveMediaNameHeader.placeholder)
    }

    func test_emptyName_fallsBackToPlaceholder() {
        XCTAssertEqual(ActiveMediaNameHeader.displayText(for: ""), ActiveMediaNameHeader.placeholder)
    }

    func test_isPlaceholder_reflectsPresence() {
        XCTAssertTrue(ActiveMediaNameHeader.isPlaceholder(for: nil))
        XCTAssertTrue(ActiveMediaNameHeader.isPlaceholder(for: ""))
        XCTAssertFalse(ActiveMediaNameHeader.isPlaceholder(for: "abc.mp3"))
    }
}
