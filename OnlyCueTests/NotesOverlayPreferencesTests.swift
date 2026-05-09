import XCTest
@testable import OnlyCue

final class NotesOverlayPreferencesTests: XCTestCase {

    func test_default_matchesShippedAppearance() {
        let prefs = NotesOverlayPreferences.default
        XCTAssertEqual(prefs.position, .bottom)
        XCTAssertEqual(prefs.fontScale, 1.0, accuracy: 0.001)
        XCTAssertEqual(prefs.textColorHex, "#FFFFFF")
        XCTAssertNil(prefs.backgroundColorHex, "default uses .ultraThinMaterial — no solid background")
        XCTAssertFalse(prefs.showCueIDPrefix)
    }

    func test_codable_roundTrip_preservesAllFields() throws {
        let original = NotesOverlayPreferences(
            position: .top,
            fontScale: 1.75,
            textColorHex: "#FF0000",
            backgroundColorHex: "#000080",
            showCueIDPrefix: true
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(NotesOverlayPreferences.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func test_decode_fontScaleAboveMax_clampsTo3() throws {
        let json = "{\"position\":\"bottom\",\"fontScale\":99.0,\"textColorHex\":\"#FFFFFF\",\"backgroundColorHex\":null,\"showCueIDPrefix\":false}"
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(NotesOverlayPreferences.self, from: data)
        XCTAssertEqual(decoded.fontScale, 3.0, accuracy: 0.001, "out-of-range fontScale must be clamped on decode")
    }

    func test_decode_fontScaleBelowMin_clampsTo075() throws {
        let json = "{\"position\":\"bottom\",\"fontScale\":0.1,\"textColorHex\":\"#FFFFFF\",\"backgroundColorHex\":null,\"showCueIDPrefix\":false}"
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(NotesOverlayPreferences.self, from: data)
        XCTAssertEqual(decoded.fontScale, 0.75, accuracy: 0.001)
    }

    func test_position_allCasesEncodeAsRawString() throws {
        for position in NotesOverlayPreferences.Position.allCases {
            let prefs = NotesOverlayPreferences(
                position: position,
                fontScale: 1.0,
                textColorHex: "#FFFFFF",
                backgroundColorHex: nil,
                showCueIDPrefix: false
            )
            let data = try JSONEncoder().encode(prefs)
            let decoded = try JSONDecoder().decode(NotesOverlayPreferences.self, from: data)
            XCTAssertEqual(decoded.position, position)
        }
    }
}
