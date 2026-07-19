import XCTest
@testable import OnlyCue

/// v16 → v17 migration (#683): `MediaItem` gains the optional `ma2PushTarget`.
/// A v16 document never wrote it, so the migration is structurally a no-op —
/// decode a `LegacyV16` snapshot and re-stamp the current schema version; every
/// item's `ma2PushTarget` comes out nil.
final class ProjectModelMigrationV17Tests: XCTestCase {

    private func v16Doc() -> String {
        """
        {
          "schemaVersion": 16,
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

    func test_v16ToV17_bumpsSchemaVersion() throws {
        let migrated = try ProjectModel.decode(from: Data(v16Doc().utf8))
        XCTAssertEqual(migrated.schemaVersion, ProjectModel.currentSchemaVersion)
    }

    func test_v16ToV17_ma2PushTargetIsNil_othersIntact() throws {
        let migrated = try ProjectModel.decode(from: Data(v16Doc().utf8))
        let item = migrated.items[0]
        XCTAssertNil(item.ma2PushTarget)
        XCTAssertEqual(item.media.displayName, "x.wav")
        XCTAssertEqual(item.startTimecodeFrames, 0)
    }
}
