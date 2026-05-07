import XCTest
@testable import OnlyCue

final class ProjectModelTests: XCTestCase {

    private static let projectID = "9F2E0F8A-9C2D-4F2A-9E1A-0E1A2D3C4B5A"
    private static let cueOneID = "11111111-1111-1111-1111-111111111111"
    private static let cueTwoID = "22222222-2222-2222-2222-222222222222"
    private static let templateProjectID = "00000000-0000-0000-0000-000000000001"

    func test_jsonRoundTrip_preservesAllFields() throws {
        let projectID = try XCTUnwrap(UUID(uuidString: Self.projectID))
        let cueOneID = try XCTUnwrap(UUID(uuidString: Self.cueOneID))
        let cueTwoID = try XCTUnwrap(UUID(uuidString: Self.cueTwoID))

        let original = ProjectModel(
            schemaVersion: 1,
            id: projectID,
            name: "Opening Number",
            media: MediaReference(
                displayName: "act1-music.wav",
                kind: .audio,
                duration: 184.32,
                bookmarkData: Data([0x01, 0x02, 0x03, 0x04])
            ),
            cues: [
                Cue(
                    id: cueOneID,
                    name: "Spot up SR",
                    time: 4.250,
                    colorHex: "#FF6B6B",
                    notes: "Wait for breath"
                ),
                Cue(
                    id: cueTwoID,
                    name: "Wash full",
                    time: 12.000,
                    colorHex: "#4ECDC4",
                    notes: ""
                )
            ]
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(original)

        let decoded = try JSONDecoder().decode(ProjectModel.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    func test_jsonRoundTrip_withNilMedia() throws {
        let original = ProjectModel(
            schemaVersion: 1,
            id: UUID(),
            name: "Empty Template",
            media: nil,
            cues: []
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ProjectModel.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    func test_encoded_isPrettyAndSortedKeys() throws {
        let projectID = try XCTUnwrap(UUID(uuidString: Self.templateProjectID))
        let model = ProjectModel(
            schemaVersion: 1,
            id: projectID,
            name: "test",
            media: nil,
            cues: []
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let json = try encoder.encode(model)
        let text = try XCTUnwrap(String(bytes: json, encoding: .utf8))

        XCTAssertTrue(text.contains("\n"), "pretty-printed output must contain newlines")
        let cuesIndex = try XCTUnwrap(text.range(of: "\"cues\"")).lowerBound
        let nameIndex = try XCTUnwrap(text.range(of: "\"name\"")).lowerBound
        XCTAssertLessThan(cuesIndex, nameIndex, "sorted keys: cues must appear before name")
    }
}
