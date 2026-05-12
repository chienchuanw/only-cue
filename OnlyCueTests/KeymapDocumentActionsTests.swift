import XCTest
@testable import OnlyCue

/// The document-window commands added to `KeymapAction` in epic #40 leaf 4
/// (`m`, `0`–`9`, Space, ←→, ↑↓) — their default chords must match the
/// literals they replaced in `DocumentView`, and the digit → slot helper must
/// be exact. Closes epic #40.
final class KeymapDocumentActionsTests: XCTestCase {

    func test_documentWindowDefaults_matchTheLiteralsTheyReplace() {
        let expected: [KeymapAction: KeyChord] = [
            .addCue: KeyChord(key: "m"),
            .playPause: KeyChord(key: "space"),
            .jumpBack: KeyChord(key: "leftArrow"),
            .jumpForward: KeyChord(key: "rightArrow"),
            .stepPrevCue: KeyChord(key: "upArrow"),
            .stepNextCue: KeyChord(key: "downArrow"),
            .addCueOfType0: KeyChord(key: "0")
        ]
        for (action, chord) in expected {
            XCTAssertEqual(Keymap.default.chord(for: action), chord, "default for \(action.rawValue)")
        }
    }

    func test_addCueOfType_mapsDigitToSlot() {
        XCTAssertEqual(KeymapAction.addCueOfType(0), .addCueOfType0)
        XCTAssertEqual(KeymapAction.addCueOfType(3), .addCueOfType3)
        XCTAssertEqual(KeymapAction.addCueOfType(9), .addCueOfType9)
        XCTAssertNil(KeymapAction.addCueOfType(10))
        XCTAssertNil(KeymapAction.addCueOfType(-1))
    }

    func test_allCueTypeSlots_haveDigitDefaults() {
        for digit in 0...9 {
            XCTAssertEqual(
                KeymapAction.addCueOfType(digit).map { Keymap.default.chord(for: $0) },
                KeyChord(key: String(digit)),
                "digit \(digit)"
            )
        }
    }

    func test_editorListsTheDocumentWindowActions() {
        let all = Set(KeymapAction.allCases)
        for action in [KeymapAction.addCue, .playPause, .jumpBack, .jumpForward, .stepPrevCue, .stepNextCue, .addCueOfType0] {
            XCTAssertTrue(all.contains(action), "\(action.rawValue) should be an editable row")
        }
    }
}
