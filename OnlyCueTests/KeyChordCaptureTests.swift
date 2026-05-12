import SwiftUI
import XCTest
@testable import OnlyCue

/// Coverage for `KeyChord.from(keyEquivalent:modifiers:)` and
/// `KeyChord.specialKeyName(for:)` — the pure mapping the Settings → Keyboard
/// editor uses to turn a captured key event into a stored chord. (Closes the
/// editor-side test bullet of epic #40 leaf 2/3.)
final class KeyChordCaptureTests: XCTestCase {

    func test_from_printableKey_keepsCharAndModifiers() {
        XCTAssertEqual(
            KeyChord.from(keyEquivalent: KeyEquivalent("e"), modifiers: [.command, .shift]),
            KeyChord(key: "e", modifiers: [.command, .shift])
        )
        XCTAssertEqual(KeyChord.from(keyEquivalent: KeyEquivalent("5"), modifiers: []), KeyChord(key: "5"))
        XCTAssertEqual(
            KeyChord.from(keyEquivalent: KeyEquivalent("="), modifiers: [.command, .option]),
            KeyChord(key: "=", modifiers: [.command, .option])
        )
    }

    func test_from_letterKey_isLowercased_caseCarriedByShift() {
        XCTAssertEqual(
            KeyChord.from(keyEquivalent: KeyEquivalent("E"), modifiers: [.shift]),
            KeyChord(key: "e", modifiers: [.shift])
        )
    }

    func test_from_specialKeys_useReservedNames() {
        XCTAssertEqual(
            KeyChord.from(keyEquivalent: .leftArrow, modifiers: [.option]),
            KeyChord(key: "leftArrow", modifiers: [.option])
        )
        XCTAssertEqual(KeyChord.from(keyEquivalent: .space, modifiers: []), KeyChord(key: "space"))
        XCTAssertEqual(KeyChord.from(keyEquivalent: .escape, modifiers: []), KeyChord(key: "escape"))
    }

    func test_from_ignoresAmbientModifiersWeDontModel() {
        // caps-lock / numeric-pad flags must not leak into the chord.
        XCTAssertEqual(
            KeyChord.from(keyEquivalent: KeyEquivalent("a"), modifiers: [.capsLock, .numericPad, .command]),
            KeyChord(key: "a", modifiers: [.command])
        )
    }

    func test_from_unbindableFunctionKey_isNil() {
        // A bare function key (private-use scalar, no printable character) can't be bound.
        XCTAssertNil(KeyChord.from(keyEquivalent: KeyEquivalent("\u{F704}"), modifiers: []))
    }

    func test_from_roundTripsThroughKeyboardShortcut() throws {
        let chord = try XCTUnwrap(KeyChord.from(keyEquivalent: .leftArrow, modifiers: [.option]))
        XCTAssertEqual(chord.keyboardShortcut, KeyboardShortcut(.leftArrow, modifiers: .option))
    }

    func test_specialKeyName() {
        XCTAssertEqual(KeyChord.specialKeyName(for: .rightArrow), "rightArrow")
        XCTAssertEqual(KeyChord.specialKeyName(for: .escape), "escape")
        XCTAssertNil(KeyChord.specialKeyName(for: KeyEquivalent("a")))
        XCTAssertNil(KeyChord.specialKeyName(for: KeyEquivalent("1")))
    }
}
