import XCTest
@testable import OnlyCue

/// v3 fixture whose cues have NO `colorHex` field. After dropping the dead
/// `colorHex` decode-only property from `LegacyV3Cue`, this should decode
/// cleanly. Before, it would throw because Swift's `Decodable` synthesis
/// requires every declared property to be present in the JSON.
private let v3FixtureWithoutColorHexOnCues = """
{
  "schemaVersion": 3,
  "id": "9F2E0F8A-9C2D-4F2A-9E1A-0E1A2D3C4B5A",
  "name": "Show",
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
          "id": "11111111-1111-1111-1111-111111111111",
          "typeID": "CCCC3333-CCCC-3333-CCCC-3333CCCC3333",
          "name": "Cue 1",
          "time": 5.0,
          "notes": ""
        }
      ]
    }
  ],
  "activeItemID": "AABBCCDD-1111-2222-3333-444455556666"
}
"""

final class ProjectModelMigrationLegacyDecodeTests: XCTestCase {

    /// Locks in the lenient-decode behavior introduced by dropping the dead
    /// `colorHex` property from `LegacyV3Cue`. Before the cleanup, decoding
    /// this fixture would throw `DecodingError.keyNotFound("colorHex")` even
    /// though the post-decode pipeline never reads colorHex anyway.
    func test_v3_decodesEvenWhenCuesAreMissingColorHex() throws {
        let model = try ProjectModel.decode(from: Data(v3FixtureWithoutColorHexOnCues.utf8))

        XCTAssertEqual(model.schemaVersion, ProjectModel.currentSchemaVersion)
        let cues = try XCTUnwrap(model.items.first?.cues)
        XCTAssertEqual(cues.count, 1)
        XCTAssertEqual(cues[0].cueNumber, 1.0, "cueNumber must still be assigned by the migration")
    }
}
