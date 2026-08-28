import XCTest
@testable import OnlyCue

/// v21 → v22 migration (#782): `MediaItem` gains the optional `colorHex` tag.
/// A v21 document has no such key, so every item must load untagged with
/// nothing else disturbed — and a v22 document must round-trip a tag.
final class ProjectModelMigrationV22Tests: XCTestCase {

    private func v21Doc() -> String {
        """
        {
          "schemaVersion": 21,
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
            "ltcMuted": true,
            "alternateName": "Overture",
            "lyrics": {"offsetSeconds": 0, "lines": []},
            "playsOriginalSourceAudio": false
          }],
          "activeItemID": "22220000-2222-0000-2222-000022220000",
          "timecodeSettings": {"framerate":"30"},
          "playbackMode": "playOnce"
        }
        """
    }

    func test_v21ToV22_bumpsSchemaVersion() throws {
        let migrated = try ProjectModel.decode(from: Data(v21Doc().utf8))
        XCTAssertEqual(migrated.schemaVersion, ProjectModel.currentSchemaVersion)
        XCTAssertGreaterThanOrEqual(ProjectModel.currentSchemaVersion, 22)
    }

    func test_v21ToV22_colorHexDefaultsNil() throws {
        let migrated = try ProjectModel.decode(from: Data(v21Doc().utf8))
        XCTAssertNil(migrated.items[0].colorHex)
    }

    func test_v21ToV22_otherFieldsIntact() throws {
        let migrated = try ProjectModel.decode(from: Data(v21Doc().utf8))
        let item = migrated.items[0]
        XCTAssertEqual(item.media.displayName, "x.wav")
        XCTAssertEqual(item.alternateName, "Overture")
        XCTAssertTrue(item.ltcMuted)
        XCTAssertEqual(migrated.name, "doc")
        XCTAssertEqual(migrated.activeItemID, item.id)
        XCTAssertEqual(migrated.timecodeSettings.framerate, .fps30)
    }

    /// The tag has to survive a save/load cycle, not just the migration — that
    /// is the whole point of putting it in the document rather than in a
    /// UI-local store.
    func test_colorHex_roundTripsThroughEncodeAndDecode() throws {
        var model = try ProjectModel.decode(from: Data(v21Doc().utf8))
        model.items[0].colorHex = CuePointType.defaultPalette[3]

        let data = try JSONEncoder().encode(model)
        let reloaded = try ProjectModel.decode(from: data)

        XCTAssertEqual(reloaded.items[0].colorHex, CuePointType.defaultPalette[3])
    }

    /// An untagged item must not write a `colorHex` key at all — otherwise
    /// every document grows a null per item for a feature most users never use.
    func test_untaggedItem_omitsTheColorHexKey() throws {
        let model = try ProjectModel.decode(from: Data(v21Doc().utf8))

        let data = try JSONEncoder().encode(model)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertFalse(json.contains("colorHex\":null"))
    }
}
