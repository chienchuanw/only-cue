import XCTest
@testable import OnlyCue

/// v15 → v16 migration: `MediaReference` gains the optional `bundlePath`. A v15
/// document never wrote it, so the migration is structurally a no-op — decode a
/// `LegacyV15` snapshot and re-stamp the current schema version; every media's
/// `bundlePath` comes out nil.
final class ProjectModelMigrationV16Tests: XCTestCase {

    private func v15Doc() -> String {
        """
        {
          "schemaVersion": 15,
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
            "lyrics": {"offsetSeconds": 0, "lines": []}
          }],
          "activeItemID": null,
          "timecodeSettings": {"framerate":"30"},
          "playbackMode": "playOnce"
        }
        """
    }

    func test_v15ToV16_bumpsSchemaVersion() throws {
        let migrated = try ProjectModel.decode(from: Data(v15Doc().utf8))
        // Legacy decodes re-stamp straight to the current version (17 as of #683).
        XCTAssertEqual(migrated.schemaVersion, ProjectModel.currentSchemaVersion)
    }

    func test_v15ToV16_mediaBundlePathIsNil_othersIntact() throws {
        let migrated = try ProjectModel.decode(from: Data(v15Doc().utf8))
        let media = migrated.items[0].media
        XCTAssertNil(media.bundlePath)
        XCTAssertEqual(media.displayName, "x.wav")
        XCTAssertEqual(media.kind, .audio)
        XCTAssertEqual(media.duration, 60)
    }
}
