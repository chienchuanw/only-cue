import XCTest
@testable import OnlyCue

/// v12 -> v13 migration: adds `MediaItem.lyrics`. Additive — every other field
/// decodes as-is; `lyrics` lands `.empty` on each item.
final class ProjectModelMigrationV13Tests: XCTestCase {

    private static let typeIDString = "AAAA0001-0000-0000-0000-000000000001"

    private func wrap(items: String, schemaVersion: Int = 12) -> String {
        """
        {
          "schemaVersion": \(schemaVersion),
          "id": "11110000-1111-0000-1111-000011110000",
          "name": "doc",
          "cuePointTypes": [{
            "id":"\(Self.typeIDString)","name":"G","colorHex":"#FFFFFF",
            "defaultFadeTime":0,"defaultNamePattern":"Cue","hotkey":null,
            "isVisible":true,"isExportEnabled":true
          }],
          "items": \(items),
          "activeItemID": null,
          "timecodeSettings": {"framerate":"30"}
        }
        """
    }

    private func v12Item(alternateName: String) -> String {
        """
        [{
          "id": "22220000-2222-0000-2222-000022220000",
          "media": {"displayName":"x.wav","kind":"audio","duration":60,"bookmarkData":"AQID"},
          "cues": [{
            "id":"BBBB0001-0000-0000-0000-000000000001","typeID":"\(Self.typeIDString)",
            "cueNumber":null,"name":"c","time":1.5,"notes":"n","fadeTime":{"fadeIn":0,"fadeOut":0}
          }],
          "startTimecodeFrames": 90,
          "ltcMuted": true,
          "alternateName": "\(alternateName)"
        }]
        """
    }

    func test_v12ToV13_decodesAndBumpsSchemaVersion() throws {
        let migrated = try ProjectModel.decode(from: Data(wrap(items: v12Item(alternateName: "Act 1")).utf8))
        XCTAssertEqual(migrated.schemaVersion, 13)
        XCTAssertEqual(ProjectModel.currentSchemaVersion, 13)
    }

    func test_v12ToV13_seedsEmptyLyricsOnEveryItem() throws {
        let migrated = try ProjectModel.decode(from: Data(wrap(items: v12Item(alternateName: "Act 1")).utf8))
        XCTAssertEqual(migrated.items[0].lyrics, Lyrics.empty)
    }

    func test_v12ToV13_preservesExistingItemFields() throws {
        let migrated = try ProjectModel.decode(from: Data(wrap(items: v12Item(alternateName: "Act 1")).utf8))
        let item = migrated.items[0]
        XCTAssertEqual(item.cues.count, 1)
        XCTAssertEqual(item.cues[0].time, 1.5, accuracy: 0.001)
        XCTAssertEqual(item.startTimecodeFrames, 90)
        XCTAssertTrue(item.ltcMuted)
        XCTAssertEqual(item.alternateName, "Act 1")
    }

    func test_currentVersionDoc_withLyrics_roundTrips() throws {
        var model = ProjectModel(
            schemaVersion: 13,
            id: UUID(),
            name: "doc",
            cuePointTypes: [CuePointType(id: UUID(), name: "G", colorHex: "#FFFFFF")],
            items: [],
            activeItemID: nil
        )
        let itemID = UUID()
        model.items = [MediaItem(
            id: itemID,
            media: MediaReference(displayName: "x.wav", kind: .audio, duration: 60, bookmarkData: Data([1])),
            cues: [],
            lyrics: Lyrics(lines: [LyricLine(time: 3, text: "hello")], offsetSeconds: 12)
        )]
        model.activeItemID = itemID

        let data = try JSONEncoder().encode(model)
        let decoded = try ProjectModel.decode(from: data)
        XCTAssertEqual(decoded.items[0].lyrics.lines.map(\.text), ["hello"])
        XCTAssertEqual(decoded.items[0].lyrics.offsetSeconds, 12)
    }

    func test_olderDoc_stillDecodes_andGetsEmptyLyrics() throws {
        let migrated = try ProjectModel.decode(from: Data(wrap(items: v12Item(alternateName: "Old")).utf8))
        XCTAssertTrue(migrated.items.allSatisfy { $0.lyrics == .empty })
    }
}
