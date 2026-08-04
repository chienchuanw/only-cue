import XCTest
@testable import OnlyCue

/// v18 → v19 migration (#715): `MediaItem` gains `playsOriginalSourceAudio`.
/// A v18 document never wrote it, so the migration is structurally a no-op —
/// decode a `LegacyV18` snapshot and re-stamp the current schema version; every
/// item's `playsOriginalSourceAudio` comes out `false` (the music-only default).
final class ProjectModelMigrationV19Tests: XCTestCase {

    private func v18Doc() -> String {
        """
        {
          "schemaVersion": 18,
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

    func test_v18ToV19_bumpsSchemaVersion() throws {
        let migrated = try ProjectModel.decode(from: Data(v18Doc().utf8))
        XCTAssertEqual(migrated.schemaVersion, ProjectModel.currentSchemaVersion)
    }

    func test_v18ToV19_playsOriginalSourceAudioDefaultsFalse() throws {
        let migrated = try ProjectModel.decode(from: Data(v18Doc().utf8))
        let item = migrated.items[0]
        XCTAssertFalse(
            item.playsOriginalSourceAudio,
            "v18 docs lack the key; migration must default to false (music-only)"
        )
    }

    func test_v18ToV19_othersFieldsIntact() throws {
        let migrated = try ProjectModel.decode(from: Data(v18Doc().utf8))
        let item = migrated.items[0]
        XCTAssertEqual(item.media.displayName, "x.wav")
        XCTAssertEqual(item.startTimecodeFrames, 0)
        XCTAssertFalse(item.ltcMuted)
    }
}
