import XCTest
@testable import OnlyCue

/// v7 fixture — has `timecodeSettings` but no per-item `tempoMap` (schema v8
/// adds the latter). Decoding it must migrate all the way to the current schema
/// (v9, which widens `cueNumber` to `Double?`) with an empty tempo map on every
/// item and the timecode settings carried through unchanged.
private let v7Fixture = """
{
  "schemaVersion": 7,
  "id": "7E7E7E7E-7E7E-7E7E-7E7E-7E7E7E7E7E7E",
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
          "cueNumber": 1,
          "name": "Cue 1",
          "time": 5.0,
          "notes": "",
          "fadeTime": { "fadeIn": 0, "fadeOut": 0 }
        }
      ]
    }
  ],
  "activeItemID": "AABBCCDD-1111-2222-3333-444455556666",
  "timecodeSettings": { "framerate": "25", "startOffsetFrames": 90000 }
}
"""

final class ProjectModelMigrationV7Tests: XCTestCase {

    func test_v7_decodesToCurrentWithEmptyTempoMapsAndPreservedTimecodeSettings() throws {
        let model = try ProjectModel.decode(from: Data(v7Fixture.utf8))

        XCTAssertEqual(model.schemaVersion, ProjectModel.currentSchemaVersion)
        XCTAssertEqual(model.items.count, 1)
        let item = try XCTUnwrap(model.items.first)
        XCTAssertTrue(item.tempoMap.isEmpty, "a migrated v7 item must have an empty tempo map")
        XCTAssertEqual(item.cues.first?.cueNumber, 1.0)
        XCTAssertEqual(model.timecodeSettings.framerate, .fps25)
        XCTAssertEqual(model.timecodeSettings.startOffsetFrames, 90_000)
    }

    func test_v8_roundTripsAPopulatedTempoMap() throws {
        let item = MediaItem(
            id: UUID(),
            media: MediaReference(displayName: "song.wav", kind: .audio, duration: 200, bookmarkData: Data([0x00])),
            cues: [],
            tempoMap: TempoMap(sections: [
                TempoSection(startSeconds: 0, bpm: 128, beatsPerBar: 4, downbeatOffsetSeconds: 0.1),
                TempoSection(startSeconds: 64, bpm: 140, beatsPerBar: 3, downbeatOffsetSeconds: 0)
            ])
        )
        let model = ProjectModel(
            schemaVersion: ProjectModel.currentSchemaVersion,
            id: UUID(),
            name: "TempoShow",
            cuePointTypes: [],
            items: [item],
            activeItemID: item.id
        )

        let data = try JSONEncoder().encode(model)
        let decoded = try ProjectModel.decode(from: data)

        XCTAssertEqual(decoded, model)
        XCTAssertEqual(decoded.items.first?.tempoMap.sections.count, 2)
        XCTAssertEqual(decoded.items.first?.tempoMap.sections.first?.bpm, 128)
    }
}
