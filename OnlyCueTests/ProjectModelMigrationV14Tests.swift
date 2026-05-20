import XCTest
@testable import OnlyCue

/// v13 → v14 migration: `LyricLine.time` becomes optional. A v13 document always
/// wrote a concrete `time` on every lyric line, so the migration is structurally
/// a no-op — it decodes the current model and stamps the new schema version.
final class ProjectModelMigrationV14Tests: XCTestCase {

    private static let typeIDString = "AAAA0001-0000-0000-0000-000000000001"

    private func v13Doc(lyricTime: String) -> String {
        """
        {
          "schemaVersion": 13,
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
            "lyrics": {"offsetSeconds": 12, "lines": [
              {"id":"CCCC0001-0000-0000-0000-000000000001","time":\(lyricTime),"text":"hello"}
            ]}
          }],
          "activeItemID": null,
          "timecodeSettings": {"framerate":"30"}
        }
        """
    }

    func test_v13ToV14_bumpsSchemaVersion() throws {
        let migrated = try ProjectModel.decode(from: Data(v13Doc(lyricTime: "3.5").utf8))
        XCTAssertEqual(migrated.schemaVersion, 14)
        XCTAssertEqual(ProjectModel.currentSchemaVersion, 14)
    }

    func test_v13ToV14_preservesPlacedLyricLine() throws {
        let migrated = try ProjectModel.decode(from: Data(v13Doc(lyricTime: "3.5").utf8))
        let lyrics = migrated.items[0].lyrics
        XCTAssertEqual(lyrics.offsetSeconds, 12)
        XCTAssertEqual(lyrics.lines.count, 1)
        XCTAssertEqual(lyrics.lines[0].time, 3.5)
        XCTAssertEqual(lyrics.lines[0].text, "hello")
    }

    func test_v14Doc_withUnplacedLine_roundTrips() throws {
        var model = ProjectModel(
            schemaVersion: 14,
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
            lyrics: Lyrics(
                lines: [LyricLine(time: 3, text: "placed"), LyricLine(time: nil, text: "unplaced")],
                offsetSeconds: 0
            )
        )]
        model.activeItemID = itemID

        let decoded = try ProjectModel.decode(from: JSONEncoder().encode(model))
        XCTAssertEqual(decoded.items[0].lyrics.placedLines.map(\.text), ["placed"])
        XCTAssertEqual(decoded.items[0].lyrics.unplacedLines.map(\.text), ["unplaced"])
    }
}
