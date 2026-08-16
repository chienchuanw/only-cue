import XCTest
@testable import OnlyCue

@MainActor
final class MiniPlaybackKeymapTests: XCTestCase {

    func test_defaultSpaceMapsToPlayPause() {
        let chord = Keymap.default.chord(for: .playPause)
        XCTAssertEqual(MiniPlaybackKeymap.action(for: chord, keymap: .default), .playPause)
    }

    func test_defaultArrowsMapToJumpAndStep() {
        XCTAssertEqual(MiniPlaybackKeymap.action(for: Keymap.default.chord(for: .jumpBack), keymap: .default), .jumpBack)
        XCTAssertEqual(MiniPlaybackKeymap.action(for: Keymap.default.chord(for: .stepNextCue), keymap: .default), .stepNextCue)
    }

    func test_rateKeysMap() {
        XCTAssertEqual(MiniPlaybackKeymap.action(for: Keymap.default.chord(for: .playbackRateUp), keymap: .default), .rateUp)
    }

    func test_goMaps() {
        XCTAssertEqual(MiniPlaybackKeymap.action(for: Keymap.default.chord(for: .go), keymap: .default), .go)
    }

    func test_excludedActionsAreIgnored() {
        // addCue is NOT a playback action — its chord must not resolve.
        XCTAssertNil(MiniPlaybackKeymap.action(for: Keymap.default.chord(for: .addCue), keymap: .default))
    }

    func test_unknownChordIsIgnored() {
        XCTAssertNil(MiniPlaybackKeymap.action(for: KeyChord(key: "q"), keymap: .default))
    }

    func test_customRebindResolves() {
        var keymap = Keymap.default
        keymap.rebind(.playPause, to: KeyChord(key: "p"))
        XCTAssertEqual(MiniPlaybackKeymap.action(for: KeyChord(key: "p"), keymap: keymap), .playPause)
    }
}
