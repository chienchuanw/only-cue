import XCTest
@testable import OnlyCue

final class CuePointTypeTests: XCTestCase {

    func test_codable_roundTrip_preservesAllFields() throws {
        let typeID = try XCTUnwrap(UUID(uuidString: "AAAA1111-AAAA-1111-AAAA-1111AAAA1111"))

        let original = CuePointType(
            id: typeID,
            name: "Lighting",
            colorHex: "#FF6B6B",
            defaultFadeTime: 2.5,
            defaultNamePattern: "Wash",
            hotkey: 1,
            isVisible: true,
            isExportEnabled: true
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CuePointType.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    func test_initWithDefaults_appliesSpecDefaults() throws {
        let id = UUID()

        let type = CuePointType(id: id, name: "General", colorHex: "#4ECDC4")

        XCTAssertEqual(type.id, id)
        XCTAssertEqual(type.name, "General")
        XCTAssertEqual(type.colorHex, "#4ECDC4")
        XCTAssertEqual(type.defaultFadeTime, 0)
        XCTAssertEqual(type.defaultNamePattern, "Cue")
        XCTAssertNil(type.hotkey)
        XCTAssertTrue(type.isVisible)
        XCTAssertTrue(type.isExportEnabled)
    }
}
