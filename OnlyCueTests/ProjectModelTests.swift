import XCTest
@testable import OnlyCue

final class ProjectModelTests: XCTestCase {

    private static let projectID = "9F2E0F8A-9C2D-4F2A-9E1A-0E1A2D3C4B5A"
    private static let itemID    = "AABBCCDD-1111-2222-3333-444455556666"
    private static let cueOneID  = "11111111-1111-1111-1111-111111111111"
    private static let cueTwoID  = "22222222-2222-2222-2222-222222222222"
    private static let templateProjectID = "00000000-0000-0000-0000-000000000001"

    func test_cuePointTypeForHotkey_returnsMatching() throws {
        let lighting = CuePointType(id: UUID(), name: "Lighting", colorHex: "#FF6B6B", hotkey: 1)
        let sound = CuePointType(id: UUID(), name: "Sound", colorHex: "#4D96FF", hotkey: 2)
        let model = ProjectModel(
            schemaVersion: ProjectModel.currentSchemaVersion,
            id: UUID(),
            name: "x",
            cuePointTypes: [lighting, sound],
            items: [],
            activeItemID: nil
        )

        XCTAssertEqual(model.cuePointType(forHotkey: 1)?.id, lighting.id)
        XCTAssertEqual(model.cuePointType(forHotkey: 2)?.id, sound.id)
    }

    func test_cuePointTypeForHotkey_returnsNilWhenUnbound() throws {
        let general = CuePointType(id: UUID(), name: "General", colorHex: "#4ECDC4")
        let model = ProjectModel(
            schemaVersion: ProjectModel.currentSchemaVersion,
            id: UUID(),
            name: "x",
            cuePointTypes: [general],
            items: [],
            activeItemID: nil
        )

        XCTAssertNil(model.cuePointType(forHotkey: 5))
    }

    func test_currentSchemaVersionIsTwelve() {
        XCTAssertEqual(ProjectModel.currentSchemaVersion, 12)
    }

    func test_colorHex_for_returnsMatchingTypeColor() throws {
        let typeID = UUID()
        let lighting = CuePointType(id: typeID, name: "Lighting", colorHex: "#FF6B6B")
        let cue = Cue(
            id: UUID(),
            typeID: typeID,
            cueNumber: 1,
            name: "Cue",
            time: 0,
            notes: "",
            fadeTime: .zero
        )
        let model = ProjectModel(
            schemaVersion: ProjectModel.currentSchemaVersion,
            id: UUID(),
            name: "x",
            cuePointTypes: [lighting],
            items: [],
            activeItemID: nil
        )

        XCTAssertEqual(model.colorHex(for: cue), "#FF6B6B")
    }

    func test_colorHex_for_danglingTypeID_returnsNil() throws {
        let cue = Cue(
            id: UUID(),
            typeID: UUID(),
            cueNumber: 1,
            name: "Cue",
            time: 0,
            notes: "",
            fadeTime: .zero
        )
        let model = ProjectModel(
            schemaVersion: ProjectModel.currentSchemaVersion,
            id: UUID(),
            name: "x",
            cuePointTypes: [],
            items: [],
            activeItemID: nil
        )

        XCTAssertNil(model.colorHex(for: cue))
    }

    func test_jsonRoundTrip_preservesAllFields() throws {
        let projectID = try XCTUnwrap(UUID(uuidString: Self.projectID))
        let itemID    = try XCTUnwrap(UUID(uuidString: Self.itemID))
        let cueOneID  = try XCTUnwrap(UUID(uuidString: Self.cueOneID))
        let cueTwoID  = try XCTUnwrap(UUID(uuidString: Self.cueTwoID))

        let item = MediaItem(
            id: itemID,
            media: MediaReference(
                displayName: "act1-music.wav",
                kind: .audio,
                duration: 184.32,
                bookmarkData: Data([0x01, 0x02, 0x03, 0x04])
            ),
            cues: [
                Cue(
                    id: cueOneID,
                    typeID: UUID(),
                    cueNumber: 1,
                    name: "Spot up SR",
                    time: 4.250,
                    notes: "Wait for breath",
                    fadeTime: .zero
                ),
                Cue(
                    id: cueTwoID,
                    typeID: UUID(),
                    cueNumber: 2,
                    name: "Wash full",
                    time: 12.000,
                    notes: "",
                    fadeTime: FadeTime(fadeIn: 1.0, fadeOut: 2.0)
                )
            ]
        )

        let original = ProjectModel(
            schemaVersion: ProjectModel.currentSchemaVersion,
            id: projectID,
            name: "Opening Number",
            items: [item],
            activeItemID: itemID
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(original)

        let decoded = try ProjectModel.decode(from: data)
        XCTAssertEqual(decoded, original)
    }

    func test_jsonRoundTrip_emptyProject() throws {
        let original = ProjectModel(
            schemaVersion: ProjectModel.currentSchemaVersion,
            id: UUID(),
            name: "Empty Template",
            items: [],
            activeItemID: nil
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try ProjectModel.decode(from: data)

        XCTAssertEqual(decoded, original)
    }

    func test_cueNumberRoundTripsThroughJSON() throws {
        let cue = Cue(
            id: UUID(),
            typeID: UUID(),
            cueNumber: 1.5,
            name: "Spot up SR",
            time: 4.25,
            notes: "",
            fadeTime: .zero
        )
        let data = try JSONEncoder().encode(cue)
        let decoded = try JSONDecoder().decode(Cue.self, from: data)
        XCTAssertEqual(decoded.cueNumber, 1.5)
    }

    func test_cueFadeTimeRoundTripsThroughJSON_split() throws {
        let cue = Cue(
            id: UUID(),
            typeID: UUID(),
            cueNumber: 1,
            name: "Wash full",
            time: 12.0,
            notes: "",
            fadeTime: FadeTime(fadeIn: 1.0, fadeOut: 2.0)
        )
        let data = try JSONEncoder().encode(cue)
        let decoded = try JSONDecoder().decode(Cue.self, from: data)
        XCTAssertEqual(decoded.fadeTime, FadeTime(fadeIn: 1.0, fadeOut: 2.0))
    }

    func test_jsonRoundTrip_withCuePointTypeAndCueReference() throws {
        let projectID = try XCTUnwrap(UUID(uuidString: Self.projectID))
        let itemID    = try XCTUnwrap(UUID(uuidString: Self.itemID))
        let cueID     = try XCTUnwrap(UUID(uuidString: Self.cueOneID))
        let typeID    = try XCTUnwrap(UUID(uuidString: "BBBB2222-BBBB-2222-BBBB-2222BBBB2222"))

        let lighting = CuePointType(id: typeID, name: "Lighting", colorHex: "#FF6B6B")
        let cue = Cue(
            id: cueID,
            typeID: typeID,
            cueNumber: 1,
            name: "Spot up SR",
            time: 4.25,
            notes: "",
            fadeTime: .zero
        )
        let item = MediaItem(
            id: itemID,
            media: MediaReference(
                displayName: "act1.wav",
                kind: .audio,
                duration: 184.32,
                bookmarkData: Data([0x01])
            ),
            cues: [cue]
        )
        let original = ProjectModel(
            schemaVersion: ProjectModel.currentSchemaVersion,
            id: projectID,
            name: "Show A",
            cuePointTypes: [lighting],
            items: [item],
            activeItemID: itemID
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try ProjectModel.decode(from: data)

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.cuePointTypes.first?.id, typeID)
        XCTAssertEqual(decoded.items.first?.cues.first?.typeID, typeID)
    }

    func test_encoded_isPrettyAndSortedKeys() throws {
        let projectID = try XCTUnwrap(UUID(uuidString: Self.templateProjectID))
        let model = ProjectModel(
            schemaVersion: ProjectModel.currentSchemaVersion,
            id: projectID,
            name: "test",
            items: [],
            activeItemID: nil
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let json = try encoder.encode(model)
        let text = try XCTUnwrap(String(bytes: json, encoding: .utf8))

        XCTAssertTrue(text.contains("\n"), "pretty-printed output must contain newlines")
        let itemsIndex = try XCTUnwrap(text.range(of: "\"items\"")).lowerBound
        let nameIndex = try XCTUnwrap(text.range(of: "\"name\"")).lowerBound
        XCTAssertLessThan(itemsIndex, nameIndex, "sorted keys: items must appear before name")
    }
}
