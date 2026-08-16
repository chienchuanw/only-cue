import AppKit
import XCTest
@testable import OnlyCue

final class MiniKeyChordTests: XCTestCase {

    func test_space() {
        XCTAssertEqual(MiniKeyChord.from(charactersIgnoringModifiers: " ", flags: []), KeyChord(key: "space"))
    }

    func test_leftArrow() {
        let left = String(UnicodeScalar(NSLeftArrowFunctionKey)!)
        XCTAssertEqual(MiniKeyChord.from(charactersIgnoringModifiers: left, flags: []), KeyChord(key: "leftArrow"))
    }

    func test_return() {
        XCTAssertEqual(MiniKeyChord.from(charactersIgnoringModifiers: "\r", flags: []), KeyChord(key: "return"))
    }

    func test_bracketWithNoModifiers() {
        XCTAssertEqual(MiniKeyChord.from(charactersIgnoringModifiers: "]", flags: []), KeyChord(key: "]"))
    }

    func test_letterLowercasedAndModifierCaptured() {
        XCTAssertEqual(
            MiniKeyChord.from(charactersIgnoringModifiers: "P", flags: [.command]),
            KeyChord(key: "p", modifiers: [.command])
        )
    }

    func test_nilCharactersYieldNil() {
        XCTAssertNil(MiniKeyChord.from(charactersIgnoringModifiers: nil, flags: []))
    }
}
