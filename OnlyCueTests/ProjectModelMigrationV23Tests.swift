import XCTest
@testable import OnlyCue

/// v22 -> v23 migration (#793): `MediaItem` gains `ltcChannelSelection` and
/// `StripedTimecodeTrack` gains optional `validFrom` / `validUntil`. A v22
/// document has none of those keys, so every item must load as `.auto` and
/// every remembered track as unbounded — which is exactly the behaviour
/// those documents already had.
final class ProjectModelMigrationV23Tests: XCTestCase {

    private func v22Doc() -> String {
        """
        {
          "schemaVersion": 22,
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
            "playsOriginalSourceAudio": false,
            "colorHex": "\(CuePointType.defaultPalette[3])"
          }],
          "activeItemID": "22220000-2222-0000-2222-000022220000",
          "timecodeSettings": {"framerate":"30"},
          "playbackMode": "playOnce"
        }
        """
    }

    /// The same fixture carrying a `rememberedLTC` written by v22. The JSON
    /// is produced by encoding a bounds-free track rather than hand-written,
    /// because `encodeIfPresent` omits both new keys for such a track — so
    /// this IS the v22 on-disk shape, and the assertion below proves it.
    private func v22DocWithRememberedLTC() throws -> String {
        let legacy = StripedTimecodeTrack(
            anchorTimecode: Timecode(frameCount: 900, rate: .fps30),
            anchorPlaybackSeconds: 2.0,
            ltcChannel: 1
        )
        let trackJSON = try XCTUnwrap(
            String(data: JSONEncoder().encode(legacy), encoding: .utf8)
        )
        XCTAssertFalse(trackJSON.contains("valid"), "a v22 track carries neither bound")
        return v22Doc().replacingOccurrences(
            of: "\"playsOriginalSourceAudio\": false",
            with: "\"playsOriginalSourceAudio\": false, \"rememberedLTC\": \(trackJSON)"
        )
    }

    func test_v22ToV23_bumpsSchemaVersion() throws {
        let migrated = try ProjectModel.decode(from: Data(v22Doc().utf8))
        XCTAssertEqual(migrated.schemaVersion, ProjectModel.currentSchemaVersion)
        XCTAssertGreaterThanOrEqual(ProjectModel.currentSchemaVersion, 23)
    }

    func test_v22ToV23_channelSelectionDefaultsToAuto() throws {
        let migrated = try ProjectModel.decode(from: Data(v22Doc().utf8))
        XCTAssertEqual(migrated.items[0].ltcChannelSelection, .auto)
    }

    func test_v22ToV23_leavesARememberedLTCUnbounded() throws {
        // The whole reason both bounds are optional: existing projects must
        // open with exactly the readout they had before (#793).
        let migrated = try ProjectModel.decode(
            from: Data(try v22DocWithRememberedLTC().utf8)
        )
        let remembered = try XCTUnwrap(migrated.items[0].rememberedLTC)
        XCTAssertNil(remembered.validFrom)
        XCTAssertNil(remembered.validUntil)
        XCTAssertTrue(remembered.isValid(atPlaybackSeconds: 9_999))
    }

    func test_v22ToV23_otherFieldsIntact() throws {
        let migrated = try ProjectModel.decode(from: Data(v22Doc().utf8))
        let item = migrated.items[0]
        XCTAssertEqual(item.media.displayName, "x.wav")
        XCTAssertEqual(item.alternateName, "Overture")
        XCTAssertTrue(item.ltcMuted)
        XCTAssertEqual(item.colorHex, CuePointType.defaultPalette[3])
        XCTAssertEqual(migrated.name, "doc")
        XCTAssertEqual(migrated.activeItemID, item.id)
        XCTAssertEqual(migrated.timecodeSettings.framerate, .fps30)
    }

    /// The choice has to survive a save/load cycle, not just the migration —
    /// that is the whole point of putting it in the document.
    func test_channelSelection_roundTripsThroughEncodeAndDecode() throws {
        var model = try ProjectModel.decode(from: Data(v22Doc().utf8))
        model.items[0].ltcChannelSelection = .channel(1)

        let reloaded = try ProjectModel.decode(from: JSONEncoder().encode(model))

        XCTAssertEqual(reloaded.items[0].ltcChannelSelection, .channel(1))
    }

    /// An item on `.auto` must not write the key at all — otherwise every
    /// document grows a field per item that only says "default". Mirrors
    /// `test_untaggedItem_omitsTheColorHexKey` in the v22 tests.
    func test_autoSelection_omitsTheKeyEntirely() throws {
        let model = try ProjectModel.decode(from: Data(v22Doc().utf8))

        let json = try XCTUnwrap(String(data: JSONEncoder().encode(model), encoding: .utf8))

        XCTAssertFalse(json.contains("ltcChannelSelection"))
    }
}
