import XCTest
@testable import OnlyCue

/// v19 → v20 migration (#754): `MediaItem` gains `rememberedLTC`. A v19 document
/// never wrote it, so the migration is structurally a no-op — re-stamp the schema
/// version; every item's `rememberedLTC` comes out nil.
final class ProjectModelMigrationV20Tests: XCTestCase {

    private func v19Doc() -> String {
        """
        {
          "schemaVersion": 19,
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
            "playsOriginalSourceAudio": false
          }],
          "activeItemID": null,
          "timecodeSettings": {"framerate":"30"},
          "playbackMode": "playOnce"
        }
        """
    }

    func test_v19ToV20_bumpsSchemaVersion() throws {
        let migrated = try ProjectModel.decode(from: Data(v19Doc().utf8))
        XCTAssertEqual(migrated.schemaVersion, ProjectModel.currentSchemaVersion)
        XCTAssertEqual(ProjectModel.currentSchemaVersion, 20)
    }

    func test_v19ToV20_rememberedLTCDefaultsNil() throws {
        let migrated = try ProjectModel.decode(from: Data(v19Doc().utf8))
        XCTAssertNil(migrated.items[0].rememberedLTC, "v19 docs lack the key; must decode to nil")
    }

    func test_v19ToV20_otherFieldsIntact() throws {
        let item = try ProjectModel.decode(from: Data(v19Doc().utf8)).items[0]
        XCTAssertEqual(item.media.displayName, "x.wav")
        XCTAssertFalse(item.ltcMuted)
        XCTAssertFalse(item.playsOriginalSourceAudio)
    }
}
