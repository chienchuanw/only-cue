import XCTest
@testable import OnlyCue

/// The eight-colour palette is now shared by two features — cue types and the
/// media colour tag (#782) — and the tag needs each colour to have a *name*,
/// because a colour with no name is unusable without colour vision.
final class CuePointTypeDefaultPaletteTests: XCTestCase {

    func test_defaultPaletteIsDerivedFromTheNamedPalette() {
        XCTAssertEqual(CuePointType.defaultPalette, CuePointType.namedDefaultPalette.map(\.hex))
    }

    /// Pins the palette itself. Changing a value here silently repaints every
    /// existing document that uses that cue type, so it must be deliberate.
    func test_paletteIsTheEightMVPColors() {
        XCTAssertEqual(CuePointType.defaultPalette, [
            "#FF6B6B", "#FFA94D", "#FFD93D", "#6BCB77",
            "#4ECDC4", "#4D96FF", "#9D7EE0", "#FF6FB5"
        ])
    }

    func test_everyPaletteEntryHasAName() {
        for entry in CuePointType.namedDefaultPalette {
            XCTAssertFalse(String(localized: entry.name).isEmpty, "\(entry.hex) has no name")
        }
    }

    func test_paletteNameLooksUpByHex() {
        let green = CuePointType.defaultPalette[3]
        XCTAssertEqual(CuePointType.paletteName(forHex: green).map { String(localized: $0) }, "Green")
    }

    /// A hand-edited `.cuelist` can carry a hex that is not in the palette. The
    /// lookup must say so rather than inventing a name.
    func test_paletteNameIsNilForAnUnknownHex() {
        XCTAssertNil(CuePointType.paletteName(forHex: "#123456"))
    }
}
