import XCTest
@testable import OnlyCue

final class ProjectModelMigrationTests: XCTestCase {

    func test_v1_withMedia_migratesToSingleItem() throws {
        let json = """
        {
          "schemaVersion": 1,
          "id": "9F2E0F8A-9C2D-4F2A-9E1A-0E1A2D3C4B5A",
          "name": "Opening Number",
          "media": {
            "displayName": "act1.wav",
            "kind": "audio",
            "duration": 184.32,
            "bookmarkData": "AQID"
          },
          "cues": [
            {
              "id": "11111111-1111-1111-1111-111111111111",
              "name": "Spot up SR",
              "time": 4.25,
              "colorHex": "#FF6B6B",
              "notes": ""
            }
          ]
        }
        """

        let model = try ProjectModel.decode(from: Data(json.utf8))

        XCTAssertEqual(model.schemaVersion, ProjectModel.currentSchemaVersion)
        XCTAssertEqual(model.name, "Opening Number")
        XCTAssertEqual(model.items.count, 1)

        let item = try XCTUnwrap(model.items.first)
        XCTAssertEqual(item.media.displayName, "act1.wav")
        XCTAssertEqual(item.media.kind, .audio)
        XCTAssertEqual(item.media.duration, 184.32, accuracy: 0.001)
        XCTAssertEqual(item.cues.count, 1)
        XCTAssertEqual(item.cues.first?.name, "Spot up SR")

        XCTAssertEqual(model.activeItemID, item.id, "the migrated item must be active")
    }

    func test_v1_withoutMedia_migratesToEmptyItems() throws {
        let json = """
        {
          "schemaVersion": 1,
          "id": "00000000-0000-0000-0000-000000000001",
          "name": "Empty",
          "media": null,
          "cues": []
        }
        """

        let model = try ProjectModel.decode(from: Data(json.utf8))

        XCTAssertEqual(model.schemaVersion, ProjectModel.currentSchemaVersion)
        XCTAssertEqual(model.items, [])
        XCTAssertNil(model.activeItemID)
    }

    func test_v2_seedsDefaultType_andAssignsToExistingCues() throws {
        let json = """
        {
          "schemaVersion": 2,
          "id": "9F2E0F8A-9C2D-4F2A-9E1A-0E1A2D3C4B5A",
          "name": "Show A",
          "items": [
            {
              "id": "AABBCCDD-1111-2222-3333-444455556666",
              "media": {
                "displayName": "act1.wav",
                "kind": "audio",
                "duration": 184.32,
                "bookmarkData": "AQID"
              },
              "cues": [
                {
                  "id": "11111111-1111-1111-1111-111111111111",
                  "name": "Spot up SR",
                  "time": 4.25,
                  "colorHex": "#FF6B6B",
                  "notes": ""
                },
                {
                  "id": "22222222-2222-2222-2222-222222222222",
                  "name": "Wash full",
                  "time": 12.0,
                  "colorHex": "#4ECDC4",
                  "notes": ""
                }
              ]
            }
          ],
          "activeItemID": "AABBCCDD-1111-2222-3333-444455556666"
        }
        """

        let model = try ProjectModel.decode(from: Data(json.utf8))

        XCTAssertEqual(model.schemaVersion, ProjectModel.currentSchemaVersion)
        XCTAssertEqual(model.cuePointTypes.count, 1, "v2 → v3 migration must seed exactly one default Type")
        let defaultType = try XCTUnwrap(model.cuePointTypes.first)
        XCTAssertEqual(defaultType.name, "General")

        let cues = try XCTUnwrap(model.items.first?.cues)
        XCTAssertEqual(cues.count, 2)
        for cue in cues {
            XCTAssertEqual(cue.typeID, defaultType.id, "every existing cue must reference the seeded default Type")
        }
    }

    func test_v1_chainsThroughV2_seedsDefaultType_andAssignsToCue() throws {
        let json = """
        {
          "schemaVersion": 1,
          "id": "9F2E0F8A-9C2D-4F2A-9E1A-0E1A2D3C4B5A",
          "name": "Opening Number",
          "media": {
            "displayName": "act1.wav",
            "kind": "audio",
            "duration": 184.32,
            "bookmarkData": "AQID"
          },
          "cues": [
            {
              "id": "11111111-1111-1111-1111-111111111111",
              "name": "Spot up SR",
              "time": 4.25,
              "colorHex": "#FF6B6B",
              "notes": ""
            }
          ]
        }
        """

        let model = try ProjectModel.decode(from: Data(json.utf8))

        XCTAssertEqual(model.schemaVersion, ProjectModel.currentSchemaVersion)
        let defaultType = try XCTUnwrap(model.cuePointTypes.first)
        XCTAssertEqual(defaultType.name, "General")
        let cue = try XCTUnwrap(model.items.first?.cues.first)
        XCTAssertEqual(cue.typeID, defaultType.id)
    }

    func test_unknownFutureVersion_throws() {
        let json = """
        {
          "schemaVersion": 999,
          "id": "00000000-0000-0000-0000-000000000001",
          "name": "Future",
          "items": [],
          "activeItemID": null
        }
        """

        do {
            _ = try ProjectModel.decode(from: Data(json.utf8))
            XCTFail("expected unsupportedSchemaVersion error")
        } catch ProjectModel.LoadError.unsupportedSchemaVersion(let version) {
            XCTAssertEqual(version, 999)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}
