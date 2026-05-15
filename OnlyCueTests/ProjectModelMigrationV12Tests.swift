import XCTest
@testable import OnlyCue

/// v11 → v12 migration (#279). Adds `MediaItem.alternateName: String?` defaulting
/// to nil. Additive only — every other field passes through unchanged.
final class ProjectModelMigrationV12Tests: XCTestCase {

    private static let typeIDString = "AAAA0001-0000-0000-0000-000000000001"

    private func cuePointTypesJSON() -> String {
        """
        [{
          "id":"\(Self.typeIDString)","name":"G","colorHex":"#fff",
          "defaultFadeTime":0,"defaultNamePattern":"Cue","hotkey":null,
          "isVisible":true,"isExportEnabled":true
        }]
        """
    }

    func test_v11ToV12_addsNilAlternateName_andPreservesOtherFields() throws {
        let json = """
        {
          "schemaVersion": 11,
          "id": "11110000-1111-0000-1111-000011110000",
          "name": "doc",
          "cuePointTypes": \(cuePointTypesJSON()),
          "items": [{
            "id": "22220000-2222-0000-2222-000022220000",
            "media": {"displayName":"song.wav","kind":"audio","duration":60,"bookmarkData":"AQID"},
            "cues": [],
            "startTimecodeFrames": 240,
            "ltcMuted": true
          }],
          "activeItemID": null,
          "timecodeSettings": {"framerate":"30"}
        }
        """.data(using: .utf8)!

        let model = try ProjectModel.decode(from: json)

        XCTAssertEqual(model.schemaVersion, ProjectModel.currentSchemaVersion)
        XCTAssertEqual(model.items.count, 1)
        let item = try XCTUnwrap(model.items.first)
        XCTAssertEqual(item.media.displayName, "song.wav")
        XCTAssertEqual(item.startTimecodeFrames, 240)
        XCTAssertTrue(item.ltcMuted)
        XCTAssertNil(item.alternateName)
    }

    func test_v12_roundTripsAlternateName() throws {
        let item = MediaItem(
            id: UUID(),
            media: MediaReference(
                displayName: "a.wav",
                kind: .audio,
                duration: 60,
                bookmarkData: Data([0x00])
            ),
            cues: [],
            startTimecodeFrames: 0,
            ltcMuted: false,
            alternateName: "Opening"
        )
        let model = ProjectModel(
            schemaVersion: ProjectModel.currentSchemaVersion,
            id: UUID(),
            name: "RT",
            items: [item],
            activeItemID: nil
        )

        let data = try JSONEncoder().encode(model)
        let decoded = try ProjectModel.decode(from: data)
        XCTAssertEqual(decoded.items.first?.alternateName, "Opening")
    }
}
