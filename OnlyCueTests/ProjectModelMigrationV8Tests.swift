import XCTest
@testable import OnlyCue

/// v8 fixture — has `timecodeSettings` and per-item `tempoMap`, with `Cue.cueNumber`
/// stored as a non-optional Double. Schema v9 widens `cueNumber` to `Double?`;
/// decoding a v8 document must preserve every cue's existing number as `.some(value)`.
private let v8Fixture = """
{
  "schemaVersion": 8,
  "id": "88888888-8888-8888-8888-888888888888",
  "name": "ShowV8",
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
          "cueNumber": 1,
          "name": "Cue 1",
          "time": 5.0,
          "notes": "",
          "fadeTime": { "fadeIn": 0, "fadeOut": 0 }
        },
        {
          "id": "22222222-2222-2222-2222-222222222222",
          "typeID": "CCCC3333-CCCC-3333-CCCC-3333CCCC3333",
          "cueNumber": 1.5,
          "name": "Cue 1.5",
          "time": 7.5,
          "notes": "",
          "fadeTime": { "fadeIn": 0, "fadeOut": 0 }
        },
        {
          "id": "33333333-3333-3333-3333-333333333333",
          "typeID": "CCCC3333-CCCC-3333-CCCC-3333CCCC3333",
          "cueNumber": 2,
          "name": "Cue 2",
          "time": 10.0,
          "notes": "",
          "fadeTime": { "fadeIn": 0, "fadeOut": 0 }
        }
      ],
      "tempoMap": { "sections": [] }
    }
  ],
  "activeItemID": "AABBCCDD-1111-2222-3333-444455556666",
  "timecodeSettings": { "framerate": "25", "startOffsetFrames": 90000 }
}
"""

final class ProjectModelMigrationV8Tests: XCTestCase {

    func test_v8_decodesToV9WithCueNumbersPreservedAsSomeValues() throws {
        let model = try ProjectModel.decode(from: Data(v8Fixture.utf8))

        XCTAssertEqual(model.schemaVersion, 9)
        let item = try XCTUnwrap(model.items.first)
        XCTAssertEqual(item.cues.count, 3)
        XCTAssertEqual(item.cues[0].cueNumber, 1.0)
        XCTAssertEqual(item.cues[1].cueNumber, 1.5)
        XCTAssertEqual(item.cues[2].cueNumber, 2.0)
        XCTAssertEqual(model.timecodeSettings.framerate, .fps25)
    }

    func test_v9_cueWithoutCueNumberDecodesToNil() throws {
        let json = """
        {
          "schemaVersion": 9,
          "id": "99999999-9999-9999-9999-999999999999",
          "name": "ShowV9",
          "cuePointTypes": [],
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
                  "name": "Unnumbered",
                  "time": 5.0,
                  "notes": "",
                  "fadeTime": { "fadeIn": 0, "fadeOut": 0 }
                }
              ],
              "tempoMap": { "sections": [] }
            }
          ],
          "activeItemID": "AABBCCDD-1111-2222-3333-444455556666",
          "timecodeSettings": { "framerate": "25", "startOffsetFrames": 0 }
        }
        """
        let model = try ProjectModel.decode(from: Data(json.utf8))
        let cue = try XCTUnwrap(model.items.first?.cues.first)
        XCTAssertNil(cue.cueNumber)
    }
}
