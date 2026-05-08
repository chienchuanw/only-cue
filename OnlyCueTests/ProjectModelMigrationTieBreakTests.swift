import XCTest
@testable import OnlyCue

/// Two cues at the *same* `time: 5.0`. JSON lists cue B (larger uuidString) BEFORE cue A
/// (smaller uuidString) so that an unstable or incidentally-stable sort by time alone
/// would put B first and assign it `cueNumber: 1`. The deterministic tie-break on
/// `id.uuidString` should always put A first regardless of input order.
private let v3FixtureWithEqualTimeCues = """
{
  "schemaVersion": 3,
  "id": "9F2E0F8A-9C2D-4F2A-9E1A-0E1A2D3C4B5A",
  "name": "Equal-time show",
  "cuePointTypes": [
    {
      "id": "CCCC3333-CCCC-3333-CCCC-3333CCCC3333",
      "name": "General",
      "colorHex": "#4ECDC4",
      "defaultFadeTime": 0,
      "defaultNamePattern": "Cue",
      "isVisible": true,
      "isExportEnabled": true
    }
  ],
  "items": [
    {
      "id": "AABBCCDD-1111-2222-3333-444455556666",
      "media": {
        "displayName": "act1.wav",
        "kind": "audio",
        "duration": 100,
        "bookmarkData": "AQID"
      },
      "cues": [
        {
          "id": "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB",
          "typeID": "CCCC3333-CCCC-3333-CCCC-3333CCCC3333",
          "name": "B",
          "time": 5.0,
          "colorHex": "#4ECDC4",
          "notes": ""
        },
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "typeID": "CCCC3333-CCCC-3333-CCCC-3333CCCC3333",
          "name": "A",
          "time": 5.0,
          "colorHex": "#4ECDC4",
          "notes": ""
        }
      ]
    }
  ],
  "activeItemID": "AABBCCDD-1111-2222-3333-444455556666"
}
"""

final class ProjectModelMigrationTieBreakTests: XCTestCase {

    func test_v3_equalTimeCues_assignCueNumbersDeterministically() throws {
        let model = try ProjectModel.decode(from: Data(v3FixtureWithEqualTimeCues.utf8))

        let cues = try XCTUnwrap(model.items.first?.cues)
        XCTAssertEqual(cues.count, 2)

        let aID = try XCTUnwrap(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let bID = try XCTUnwrap(UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB"))

        // Cue A (smaller uuidString) must always land at cueNumber 1, regardless of JSON order.
        // Cue B (larger uuidString) must always land at cueNumber 2.
        let cueA = try XCTUnwrap(cues.first(where: { $0.id == aID }))
        let cueB = try XCTUnwrap(cues.first(where: { $0.id == bID }))
        XCTAssertEqual(cueA.cueNumber, 1.0, "smaller-uuidString cue must win the tie-break and get the lower cueNumber")
        XCTAssertEqual(cueB.cueNumber, 2.0, "larger-uuidString cue must lose the tie-break and get the higher cueNumber")
    }

    func test_v3_equalTimeCues_migrationIsIdempotent() throws {
        let firstRun = try ProjectModel.decode(from: Data(v3FixtureWithEqualTimeCues.utf8))
        let secondRun = try ProjectModel.decode(from: Data(v3FixtureWithEqualTimeCues.utf8))

        let firstCues = try XCTUnwrap(firstRun.items.first?.cues)
        let secondCues = try XCTUnwrap(secondRun.items.first?.cues)

        // The same JSON decoded twice must produce identical (id, cueNumber) pairings.
        let firstMap = Dictionary(uniqueKeysWithValues: firstCues.map { ($0.id, $0.cueNumber) })
        let secondMap = Dictionary(uniqueKeysWithValues: secondCues.map { ($0.id, $0.cueNumber) })
        XCTAssertEqual(firstMap, secondMap, "re-running the migration on the same JSON must produce identical cueNumber assignments")
    }
}
