import XCTest
@testable import OnlyCue

/// Coverage for `ProjectTimecodeSettings` after the schema-v10 reshape: the
/// project owns only `framerate`; the start TC now lives on each `MediaItem`
/// as `startTimecodeFrames`. The mapping function takes the active item.
final class ProjectTimecodeSettingsTests: XCTestCase {

    // MARK: - ProjectTimecodeSettings value type

    func test_default_is30fps() {
        XCTAssertEqual(ProjectTimecodeSettings.default.framerate, .fps30)
    }

    func test_timecode_addsItemStartAndPlaybackPosition() {
        // 25 fps, item start 01:00:00:00, play at 30 s → 01:00:30:00.
        let settings = ProjectTimecodeSettings(framerate: .fps25)
        let item = Self.item(startTimecodeFrames: 90_000)
        XCTAssertEqual(settings.timecode(atPlaybackSeconds: 30, forItem: item).displayString, "01:00:30:00")
        XCTAssertEqual(settings.timecode(atPlaybackSeconds: 0, forItem: item).displayString, "01:00:00:00")
    }

    func test_timecode_dropFrame() {
        // 60 real seconds at 30 fps DF = 1800 frames elapsed → label 00:01:00;02.
        let settings = ProjectTimecodeSettings(framerate: .fps30drop)
        let item = Self.item(startTimecodeFrames: 0)
        XCTAssertEqual(settings.timecode(atPlaybackSeconds: 60, forItem: item).displayString, "00:01:00;02")
    }

    func test_timecode_clampsNegativePlayback() {
        let settings = ProjectTimecodeSettings(framerate: .fps30)
        let item = Self.item(startTimecodeFrames: 300)
        XCTAssertEqual(
            settings.timecode(atPlaybackSeconds: -5, forItem: item),
            Timecode(frameCount: 300, rate: .fps30)
        )
    }

    func test_timecode_perItemMapping_distinctItemsYieldDistinctTCs() {
        // The motivating case for the v10 reshape: two items with distinct
        // start TCs share one project framerate but produce distinct readouts.
        let settings = ProjectTimecodeSettings(framerate: .fps25)
        let item1 = Self.item(startTimecodeFrames: 90_000)   // 01:00:00:00
        let item2 = Self.item(startTimecodeFrames: 112_500)  // 01:15:00:00
        XCTAssertEqual(settings.timecode(atPlaybackSeconds: 0, forItem: item1).displayString, "01:00:00:00")
        XCTAssertEqual(settings.timecode(atPlaybackSeconds: 0, forItem: item2).displayString, "01:15:00:00")
    }

    func test_codable_roundTrip() throws {
        let settings = ProjectTimecodeSettings(framerate: .fps24)
        let decoded = try JSONDecoder().decode(
            ProjectTimecodeSettings.self,
            from: try JSONEncoder().encode(settings)
        )
        XCTAssertEqual(decoded, settings)
    }

    func test_jsonShape_tolerates_legacyStartOffsetFramesKey() throws {
        // v9 payloads that haven't been migrated yet may still carry
        // `startOffsetFrames` on `timecodeSettings`. The current struct must
        // decode them cleanly (ignoring the legacy key) — the v9 → v10
        // migration handles the actual data fan-out.
        let decoded = try JSONDecoder().decode(
            ProjectTimecodeSettings.self,
            from: Data(#"{"framerate":"30df","startOffsetFrames":7}"#.utf8)
        )
        XCTAssertEqual(decoded.framerate, .fps30drop)
    }

    // MARK: - Schema chain still produces current schema

    func test_v6Document_migratesToCurrent_withDefaultTimecodeSettings() throws {
        let model = try ProjectModel.decode(from: Data(Self.v6FixtureJSON.utf8))
        XCTAssertEqual(model.schemaVersion, ProjectModel.currentSchemaVersion)
        XCTAssertEqual(model.timecodeSettings, .default)
    }

    func test_newDocument_startsAtCurrentSchemaWithDefaultTimecodeSettings() {
        let document = CueListDocument()
        XCTAssertEqual(document.model.schemaVersion, ProjectModel.currentSchemaVersion)
        XCTAssertEqual(document.model.timecodeSettings, .default)
    }

    // MARK: - Helpers

    private static func item(startTimecodeFrames: Int) -> MediaItem {
        MediaItem(
            id: UUID(),
            media: MediaReference(
                displayName: "fixture.wav",
                kind: .audio,
                duration: 10,
                bookmarkData: Data()
            ),
            cues: [],
            startTimecodeFrames: startTimecodeFrames,
            ltcMuted: false
        )
    }

    private static let v6FixtureJSON = """
    {
      "schemaVersion": 6,
      "id": "9F2E0F8A-9C2D-4F2A-9E1A-0E1A2D3C4B5A",
      "name": "Legacy v6 show",
      "activeItemID": null,
      "cuePointTypes": [
        {
          "id": "CCCC3333-CCCC-3333-CCCC-3333CCCC3333",
          "name": "General",
          "colorHex": "#4ECDC4",
          "defaultFadeTime": 0,
          "defaultNamePattern": "Cue",
          "hotkey": null,
          "isVisible": true,
          "isExportEnabled": true
        }
      ],
      "items": []
    }
    """
}
