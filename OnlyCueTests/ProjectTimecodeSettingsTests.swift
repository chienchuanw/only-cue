import XCTest
@testable import OnlyCue

/// Coverage for `ProjectTimecodeSettings` (epic #33 leaf 4 — the project's
/// persisted framerate + start offset) and the v6 → v7 schema migration.
final class ProjectTimecodeSettingsTests: XCTestCase {

    // MARK: - ProjectTimecodeSettings value type

    func test_default_is30fpsZeroOffset() {
        XCTAssertEqual(ProjectTimecodeSettings.default.framerate, .fps30)
        XCTAssertEqual(ProjectTimecodeSettings.default.startOffsetFrames, 0)
        XCTAssertEqual(ProjectTimecodeSettings.default.startTimecode, Timecode(frameCount: 0, rate: .fps30))
    }

    func test_startTimecode_isTheOffsetAsATimecode() throws {
        let oneHourAt25 = try XCTUnwrap(Timecode(hours: 1, minutes: 0, seconds: 0, frames: 0, rate: .fps25))
        let settings = ProjectTimecodeSettings(framerate: .fps25, startOffsetFrames: oneHourAt25.frameCount)
        XCTAssertEqual(settings.startOffsetFrames, 90_000)
        XCTAssertEqual(settings.startTimecode.displayString, "01:00:00:00")
    }

    func test_timecodeAtPlaybackSeconds_addsOffsetAndPosition() {
        // The epic-acceptance case: 25 fps, start offset 01:00:00:00, play at 30 s past start → 01:00:30:00.
        let settings = ProjectTimecodeSettings(framerate: .fps25, startOffsetFrames: 90_000)
        XCTAssertEqual(settings.timecode(atPlaybackSeconds: 30).displayString, "01:00:30:00")
        XCTAssertEqual(settings.timecode(atPlaybackSeconds: 0).displayString, "01:00:00:00")
    }

    func test_timecodeAtPlaybackSeconds_dropFrame() {
        // 60 real seconds at 30 fps DF = 1800 frames elapsed → label 00:01:00;02 (numbers ;00/;01 skipped).
        let settings = ProjectTimecodeSettings(framerate: .fps30drop, startOffsetFrames: 0)
        XCTAssertEqual(settings.timecode(atPlaybackSeconds: 60).displayString, "00:01:00;02")
    }

    func test_timecodeAtPlaybackSeconds_clampsNegativePlayback() {
        let settings = ProjectTimecodeSettings(framerate: .fps30, startOffsetFrames: 300)
        XCTAssertEqual(settings.timecode(atPlaybackSeconds: -5), Timecode(frameCount: 300, rate: .fps30))
    }

    func test_codable_roundTrip() throws {
        let settings = ProjectTimecodeSettings(framerate: .fps24, startOffsetFrames: 123)
        let decoded = try JSONDecoder().decode(ProjectTimecodeSettings.self, from: try JSONEncoder().encode(settings))
        XCTAssertEqual(decoded, settings)
    }

    func test_jsonShape_usesFramerateRawValue() throws {
        let json = try JSONDecoder().decode(
            ProjectTimecodeSettings.self,
            from: Data(#"{"framerate":"30df","startOffsetFrames":7}"#.utf8)
        )
        XCTAssertEqual(json.framerate, .fps30drop)
        XCTAssertEqual(json.startOffsetFrames, 7)
    }

    // MARK: - Schema v6 → v7 migration

    func test_v6Document_migratesToV7_withDefaultTimecodeSettings() throws {
        let model = try ProjectModel.decode(from: Data(Self.v6FixtureJSON.utf8))
        XCTAssertEqual(model.schemaVersion, ProjectModel.currentSchemaVersion)
        XCTAssertEqual(model.timecodeSettings, .default)
        XCTAssertEqual(model.name, "Legacy v6 show")
        XCTAssertEqual(model.cuePointTypes.map(\.name), ["General"])
    }

    func test_v7Document_roundTrips_preservingTimecodeSettings() throws {
        let original = ProjectModel(
            schemaVersion: ProjectModel.currentSchemaVersion,
            id: UUID(),
            name: "v7 show",
            cuePointTypes: [ProjectModel.makeDefaultCuePointType()],
            items: [],
            activeItemID: nil,
            timecodeSettings: ProjectTimecodeSettings(framerate: .fps25, startOffsetFrames: 90_000)
        )
        let reloaded = try ProjectModel.decode(from: try JSONEncoder().encode(original))
        XCTAssertEqual(reloaded, original)
        XCTAssertEqual(reloaded.timecodeSettings.framerate, .fps25)
        XCTAssertEqual(reloaded.timecodeSettings.startOffsetFrames, 90_000)
    }

    func test_newDocument_startsAtCurrentSchemaWithDefaultTimecodeSettings() {
        let document = CueListDocument()
        XCTAssertEqual(document.model.schemaVersion, ProjectModel.currentSchemaVersion)
        XCTAssertEqual(document.model.timecodeSettings, .default)
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
