import XCTest
@testable import OnlyCue

/// v9 → v10 migration. Schema v10 drops the project-wide
/// `timecodeSettings.startOffsetFrames` and fans it onto every
/// `MediaItem.startTimecodeFrames`, plus introduces `MediaItem.ltcMuted`
/// (defaults to false). Tests pin: every existing item inherits the old
/// project-wide offset verbatim, every item gets `ltcMuted = false`, and
/// zero-offset projects round-trip losslessly.
private let v9FixtureWithProjectOffset = """
{
  "schemaVersion": 9,
  "id": "AAAA9999-AAAA-9999-AAAA-9999AAAA9999",
  "name": "ShowV9",
  "cuePointTypes": [],
  "items": [
    {
      "id": "11110000-1111-0000-1111-000011110000",
      "media": {
        "displayName": "act1.wav",
        "kind": "audio",
        "duration": 60,
        "bookmarkData": "AQID"
      },
      "cues": [],
      "tempoMap": { "sections": [] }
    },
    {
      "id": "22220000-2222-0000-2222-000022220000",
      "media": {
        "displayName": "act2.wav",
        "kind": "audio",
        "duration": 90,
        "bookmarkData": "AQID"
      },
      "cues": [],
      "tempoMap": { "sections": [] }
    }
  ],
  "activeItemID": null,
  "timecodeSettings": { "framerate": "25", "startOffsetFrames": 90000 }
}
"""

private let v9FixtureWithZeroOffset = """
{
  "schemaVersion": 9,
  "id": "BBBB9999-BBBB-9999-BBBB-9999BBBB9999",
  "name": "ZeroOffset",
  "cuePointTypes": [],
  "items": [
    {
      "id": "33330000-3333-0000-3333-000033330000",
      "media": {
        "displayName": "single.wav",
        "kind": "audio",
        "duration": 30,
        "bookmarkData": "AQID"
      },
      "cues": [],
      "tempoMap": { "sections": [] }
    }
  ],
  "activeItemID": null,
  "timecodeSettings": { "framerate": "30", "startOffsetFrames": 0 }
}
"""

final class ProjectModelMigrationV10Tests: XCTestCase {

    func test_v9ToV10_fansProjectWideOffsetOntoEveryItem() throws {
        let model = try ProjectModel.decode(from: Data(v9FixtureWithProjectOffset.utf8))

        XCTAssertEqual(model.schemaVersion, 11)
        XCTAssertEqual(model.items.count, 2)
        XCTAssertTrue(model.items.allSatisfy { $0.startTimecodeFrames == 90_000 })
        XCTAssertTrue(model.items.allSatisfy { $0.ltcMuted == false })
        XCTAssertEqual(model.timecodeSettings.framerate, .fps25)
    }

    func test_v9ToV10_zeroOffset_yieldsZeroOnEveryItem() throws {
        let model = try ProjectModel.decode(from: Data(v9FixtureWithZeroOffset.utf8))

        XCTAssertEqual(model.schemaVersion, 11)
        XCTAssertEqual(model.items.first?.startTimecodeFrames, 0)
        XCTAssertEqual(model.items.first?.ltcMuted, false)
    }
}
