import XCTest
@testable import OnlyCue

/// v20 → v21 migration (#764): `MA2PushTarget.executorPage` / `executorNumber` become
/// optional. A v20 document stored both as plain `Int`s, which decode straight into the
/// new `Int?` — so a saved executor is preserved and the schema version is re-stamped.
final class ProjectModelMigrationV21Tests: XCTestCase {

    private func v20Doc() -> String {
        """
        {
          "schemaVersion": 20,
          "id": "11110000-1111-0000-1111-000011110000",
          "name": "doc",
          "cuePointTypes": [{
            "id":"AAAA0001-0000-0000-0000-000000000001","name":"G","colorHex":"#FFFFFF",
            "defaultFadeTime":0,"defaultNamePattern":"Cue","hotkey":null,
            "isVisible":true,"isExportEnabled":true
          }],
          "items": [{
            "id": "22220000-2222-0000-2222-000022220000",
            "media": {"displayName":"x.wav","kind":"audio","duration":60,"bookmarkData":"AQID"},
            "cues": [],
            "startTimecodeFrames": 0,
            "ltcMuted": false,
            "alternateName": null,
            "lyrics": {"offsetSeconds": 0, "lines": []},
            "playsOriginalSourceAudio": false,
            "ma2PushTarget": {
              "sequenceSlot": 12, "timecodeSlot": 3,
              "executorPage": 2, "executorNumber": 5,
              "timecodeCommand": "goto", "includedTypeIDs": []
            }
          }],
          "activeItemID": null,
          "timecodeSettings": {"framerate":"30"},
          "playbackMode": "playOnce"
        }
        """
    }

    func test_v20ToV21_bumpsSchemaVersion() throws {
        let migrated = try ProjectModel.decode(from: Data(v20Doc().utf8))
        XCTAssertEqual(migrated.schemaVersion, ProjectModel.currentSchemaVersion)
        // Floor, not a pin: this test owns "v20 documents still load", not
        // "the schema is exactly 21". The exact-version tripwire lives once, in
        // ProjectModelTests, so a bump doesn't ripple through every migration
        // suite. Matches the V20 suite's idiom.
        XCTAssertGreaterThanOrEqual(ProjectModel.currentSchemaVersion, 21)
    }

    func test_v20ToV21_preservesIntExecutor() throws {
        let target = try ProjectModel.decode(from: Data(v20Doc().utf8)).items[0].ma2PushTarget
        XCTAssertEqual(target?.executor?.page, 2)
        XCTAssertEqual(target?.executor?.number, 5)
        XCTAssertEqual(target?.sequenceSlot, 12)
    }

    func test_v20ToV21_otherFieldsIntact() throws {
        let item = try ProjectModel.decode(from: Data(v20Doc().utf8)).items[0]
        XCTAssertEqual(item.media.displayName, "x.wav")
        XCTAssertFalse(item.ltcMuted)
    }
}
