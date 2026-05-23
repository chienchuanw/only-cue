import XCTest
@testable import OnlyCue

/// v14 -> v15 migration: adds `ProjectModel.playbackMode` defaulting to
/// `.playOnce`. Additive — every other field decodes as-is.
final class ProjectModelMigrationV15Tests: XCTestCase {

    private static let typeIDString = "AAAA0001-0000-0000-0000-000000000001"

    private func v14Doc() -> String {
        """
        {
          "schemaVersion": 14,
          "id": "11110000-1111-0000-1111-000011110000",
          "name": "doc",
          "cuePointTypes": [{
            "id":"\(Self.typeIDString)","name":"G","colorHex":"#FFFFFF",
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
            "lyrics": {"lines": [], "offsetSeconds": 0}
          }],
          "activeItemID": null,
          "timecodeSettings": {"framerate":"30"}
        }
        """
    }

    func test_v14ToV15_decodesAndBumpsSchemaVersion() throws {
        let migrated = try ProjectModel.decode(from: Data(v14Doc().utf8))
        XCTAssertEqual(migrated.schemaVersion, ProjectModel.currentSchemaVersion)
    }

    func test_v14ToV15_defaultsPlaybackModeToPlayOnce() throws {
        let migrated = try ProjectModel.decode(from: Data(v14Doc().utf8))
        XCTAssertEqual(migrated.playbackMode, .playOnce)
    }

    func test_v14ToV15_preservesItems() throws {
        let migrated = try ProjectModel.decode(from: Data(v14Doc().utf8))
        XCTAssertEqual(migrated.items.count, 1)
        XCTAssertEqual(migrated.items[0].media.displayName, "x.wav")
    }

    func test_currentVersionDoc_roundTripsWithExplicitPlaybackMode() throws {
        var model = ProjectModel(
            schemaVersion: ProjectModel.currentSchemaVersion,
            id: UUID(),
            name: "round",
            items: [],
            activeItemID: nil
        )
        model.playbackMode = .loop

        let data = try JSONEncoder().encode(model)
        let decoded = try ProjectModel.decode(from: data)

        XCTAssertEqual(decoded.playbackMode, .loop)
    }
}
