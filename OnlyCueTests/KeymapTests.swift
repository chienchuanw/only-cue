import SwiftUI
import XCTest
@testable import OnlyCue

/// Schema / conflict-detection / persistence coverage for `Keymap` and
/// `KeyChord` — the data layer behind epic #40's custom keyboard shortcuts
/// editor. Pure value types, so no `@MainActor`. (Closes epic #40 leaf 5 for
/// the load / save / conflict-detection cases; the `UserDefaults` round-trip
/// itself is in `KeymapStoreTests`.)
final class KeymapTests: XCTestCase {

    // MARK: - Defaults

    func test_defaultKeymap_bindsEveryAction() {
        for action in KeymapAction.allCases {
            XCTAssertNotNil(Keymap.defaultBindings[action], "no default binding for \(action.rawValue)")
        }
        XCTAssertEqual(Keymap.default.bindings.count, KeymapAction.allCases.count)
    }

    func test_defaultKeymap_isConflictFree() {
        XCTAssertTrue(Keymap.default.conflicts().isEmpty, "default bindings collide: \(Keymap.default.conflicts())")
    }

    func test_chordForAction_matchesDefaults() {
        XCTAssertEqual(Keymap.default.chord(for: .exportCues), KeyChord(key: "e", modifiers: [.command, .shift]))
        XCTAssertEqual(Keymap.default.chord(for: .snapSelectedCueToPlayhead), KeyChord(key: "s"))
        XCTAssertEqual(Keymap.default.chord(for: .addCueOfType3), KeyChord(key: "3"))
    }

    // MARK: - JSON round-trip

    func test_jsonRoundTrip_preservesEveryBinding() throws {
        let decoded = try JSONDecoder().decode(Keymap.self, from: try Keymap.default.encoded())
        XCTAssertEqual(decoded, .default)
    }

    func test_jsonRoundTrip_afterRebind() throws {
        var map = Keymap.default
        map.rebind(.duplicateCueAtPlayhead, to: KeyChord(key: "k", modifiers: [.command, .shift]))
        let decoded = try JSONDecoder().decode(Keymap.self, from: try map.encoded())
        XCTAssertEqual(decoded, map)
        XCTAssertEqual(decoded.chord(for: .duplicateCueAtPlayhead), KeyChord(key: "k", modifiers: [.command, .shift]))
    }

    // MARK: - Lenient decode

    func test_decode_nilData_isDefault() {
        XCTAssertEqual(Keymap.decode(nil), .default)
    }

    func test_decode_corruptData_isDefault() {
        XCTAssertEqual(Keymap.decode(Data("not json at all".utf8)), .default)
    }

    func test_decode_unknownActionKey_isDropped_knownKeptOverridden() {
        let json = """
        { "importMedia": { "key": "i", "modifiers": ["command"] },
          "thisIsNotAnAction": { "key": "z", "modifiers": [] } }
        """
        let map = Keymap.decode(Data(json.utf8))
        XCTAssertEqual(map.chord(for: .importMedia), KeyChord(key: "i", modifiers: [.command]))
        XCTAssertEqual(map.bindings.count, KeymapAction.allCases.count, "unknown key must not add a binding")
    }

    func test_decode_partialMap_backfillsMissingActionsFromDefaults() {
        let json = #"{ "exportCues": { "key": "x", "modifiers": ["command"] } }"#
        let map = Keymap.decode(Data(json.utf8))
        XCTAssertEqual(map.chord(for: .exportCues), KeyChord(key: "x", modifiers: [.command]))
        XCTAssertEqual(map.chord(for: .importMedia), Keymap.default.chord(for: .importMedia))
        XCTAssertEqual(map.bindings.count, KeymapAction.allCases.count)
    }

    // MARK: - Conflict detection

    func test_actionsConflicting_predictsACollisionBeforeRebinding() {
        let map = Keymap.default
        let exportChord = map.chord(for: .exportCues)
        // Binding importMedia to exportCues' chord would collide with exportCues…
        XCTAssertEqual(map.actionsConflicting(with: exportChord, excluding: .importMedia), [.exportCues])
        // …but a fresh, unused chord collides with nothing.
        XCTAssertTrue(map.actionsConflicting(with: KeyChord(key: "j", modifiers: [.command, .control]),
                                             excluding: .importMedia).isEmpty)
    }

    func test_rebind_intoAnotherActionsChord_isReportedAsConflict() {
        var map = Keymap.default
        let exportChord = map.chord(for: .exportCues)
        XCTAssertTrue(map.conflicts().isEmpty)

        map.rebind(.importMedia, to: exportChord)
        XCTAssertEqual(map.actionsConflicting(with: exportChord, excluding: .importMedia), [.exportCues])

        let collisions = map.conflicts()
        XCTAssertEqual(collisions.count, 1)
        XCTAssertEqual(collisions[exportChord].map(Set.init), Set([.importMedia, .exportCues]))
    }

    func test_rebind_thatDoesNotCollide_keepsMapConflictFree() {
        var map = Keymap.default
        map.rebind(.duplicateCueAtPlayhead, to: KeyChord(key: "9", modifiers: [.command, .control]))
        XCTAssertTrue(map.conflicts().isEmpty)
    }

    func test_rebindChangesOnlyThatAction() {
        var map = Keymap.default
        let before = map.chord(for: .exportCues)
        map.rebind(.importMedia, to: KeyChord(key: "i", modifiers: [.command, .shift]))
        XCTAssertEqual(map.chord(for: .exportCues), before)
        XCTAssertEqual(map.chord(for: .importMedia), KeyChord(key: "i", modifiers: [.command, .shift]))
    }

    // MARK: - Reset

    func test_resetToDefault_restoresOneAction() {
        var map = Keymap.default
        map.rebind(.exportCues, to: KeyChord(key: "q"))
        map.resetToDefault(.exportCues)
        XCTAssertEqual(map.chord(for: .exportCues), Keymap.default.chord(for: .exportCues))
    }

    func test_resetAll_restoresWholeDefaultMap() {
        var map = Keymap.default
        map.rebind(.exportCues, to: KeyChord(key: "q"))
        map.rebind(.importMedia, to: KeyChord(key: "w"))
        map.resetAll()
        XCTAssertEqual(map, .default)
    }

    // MARK: - KeyChord ⇄ SwiftUI

    func test_keyChord_toKeyboardShortcut_roundTripsKeyAndModifiers() throws {
        let shortcut = try XCTUnwrap(KeyChord(key: "e", modifiers: [.command, .shift]).keyboardShortcut)
        XCTAssertEqual(shortcut, KeyboardShortcut("e", modifiers: [.command, .shift]))
    }

    func test_keyChord_specialKey_toKeyboardShortcut() throws {
        let shortcut = try XCTUnwrap(KeyChord(key: "leftArrow", modifiers: [.option]).keyboardShortcut)
        XCTAssertEqual(shortcut, KeyboardShortcut(.leftArrow, modifiers: .option))
    }

    func test_keyChord_unparseableKey_hasNoShortcut() {
        XCTAssertNil(KeyChord(key: "notakey").keyboardShortcut)
        XCTAssertNil(KeyChord(key: "").keyboardShortcut)
    }

    func test_keyChord_displayString() {
        XCTAssertEqual(KeyChord(key: "e", modifiers: [.command, .shift]).displayString, "⇧⌘E")
        XCTAssertEqual(KeyChord(key: "leftArrow", modifiers: [.option]).displayString, "⌥←")
        XCTAssertEqual(KeyChord(key: "s").displayString, "S")
        XCTAssertEqual(KeyChord(key: "0", modifiers: [.command, .option]).displayString, "⌥⌘0")
    }

    func test_keyChord_jsonRoundTrip() throws {
        let chord = KeyChord(key: "rightArrow", modifiers: [.option, .shift])
        let decoded = try JSONDecoder().decode(KeyChord.self, from: try JSONEncoder().encode(chord))
        XCTAssertEqual(decoded, chord)
    }
}
