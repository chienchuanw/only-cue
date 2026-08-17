import XCTest
@testable import OnlyCue

/// Unit tests for the Mini Player's pure display model (macOS, #748).
/// Spec: docs/superpowers/specs/2026-08-16-miniplay-design.md.
final class MiniPlayerModelTests: XCTestCase {

    // Fixed cue-type IDs so colour lookups are deterministic.
    private let amberID = UUID()
    private let tealID = UUID()

    private func types() -> [CuePointType] {
        [
            CuePointType(id: amberID, name: "Amber", colorHex: "#FFA94D"),
            CuePointType(id: tealID, name: "Teal", colorHex: "#4ECDC4")
        ]
    }

    private func cue(_ number: Double, _ name: String, _ time: TimeInterval, _ typeID: UUID) -> Cue {
        Cue(id: UUID(), typeID: typeID, cueNumber: number, name: name, time: time, notes: "", fadeTime: .zero)
    }

    private func item(startTimecodeFrames: Int = 0) -> MediaItem {
        MediaItem(
            id: UUID(),
            media: MediaReference(
                displayName: "Dialogue — Scene 2.wav",
                kind: .audio,
                duration: 120,
                bookmarkData: Data([0x00])
            ),
            cues: [
                cue(1, "Lights Up", 10, amberID),
                cue(2, "Verse 1", 30, tealID),
                cue(3, "Chorus", 60, amberID)
            ],
            startTimecodeFrames: startTimecodeFrames
        )
    }

    private let settings = ProjectTimecodeSettings(framerate: .fps30)

    // MARK: - Empty state

    func test_noMedia_isEmptyWithZeroReadout() {
        let model = MiniPlayerModel.make(
            currentTime: 0,
            item: nil,
            timecodeSettings: settings,
            cuePointTypes: types(),
            editorMode: .cue
        )
        XCTAssertTrue(model.isEmpty)
        XCTAssertEqual(model.mediaName, "No media loaded")
        XCTAssertEqual(model.timecode, "00:00:00:00")
        XCTAssertEqual(model.framerateLabel, "30 fps")
        XCTAssertNil(model.currentCue)
        XCTAssertNil(model.nextCue)
        XCTAssertFalse(model.showsGo)
    }

    // MARK: - Cue mode: current / next / timecode

    func test_cueMode_currentAndNextAndTimecode() {
        let model = MiniPlayerModel.make(
            currentTime: 35,
            item: item(),
            timecodeSettings: settings,
            cuePointTypes: types(),
            editorMode: .cue
        )
        XCTAssertFalse(model.isEmpty)
        XCTAssertEqual(model.mediaName, "Dialogue — Scene 2.wav")
        XCTAssertEqual(model.timecode, "00:00:35:00")            // 35s @ 30fps, start 0

        // active cue at 35s is cue #2 (Verse 1, Teal)
        XCTAssertEqual(model.currentCue?.number, FadeTime.formatNumber(2))
        XCTAssertEqual(model.currentCue?.name, "Verse 1")
        XCTAssertEqual(model.currentCue?.colorHex, "#4ECDC4")

        // next cue is #3 (Chorus, Amber) at 60s → interval 25s
        XCTAssertEqual(model.nextCue?.cue.number, FadeTime.formatNumber(3))
        XCTAssertEqual(model.nextCue?.cue.name, "Chorus")
        XCTAssertEqual(model.nextCue?.cue.colorHex, "#FFA94D")
        XCTAssertEqual(
            model.nextCue?.countdown,
            TransportBar.countdownLabel(mode: .time, interval: 25, activeTempo: nil, rate: .fps30)
        )
        XCTAssertFalse(model.showsGo)
    }

    func test_timecode_respectsStartTimecodeFrames() {
        let model = MiniPlayerModel.make(
            currentTime: 35,
            item: item(startTimecodeFrames: 30 * 3600), // 01:00:00:00 start
            timecodeSettings: settings,
            cuePointTypes: types(),
            editorMode: .cue
        )
        XCTAssertEqual(model.timecode, "01:00:35:00")
    }

    func test_beforeFirstCue_noCurrentButNextIsFirst() {
        let model = MiniPlayerModel.make(
            currentTime: 2,
            item: item(),
            timecodeSettings: settings,
            cuePointTypes: types(),
            editorMode: .cue
        )
        XCTAssertNil(model.currentCue)
        XCTAssertEqual(model.nextCue?.cue.name, "Lights Up")
    }

    func test_pastLastCue_noNext() {
        let model = MiniPlayerModel.make(
            currentTime: 90,
            item: item(),
            timecodeSettings: settings,
            cuePointTypes: types(),
            editorMode: .cue
        )
        XCTAssertEqual(model.currentCue?.name, "Chorus")
        XCTAssertNil(model.nextCue)
    }

    // MARK: - Progress bar (#758): progress fraction + length label

    func test_progress_and_lengthLabel() {
        let model = MiniPlayerModel.make(
            currentTime: 30,
            duration: 120,
            item: item(),
            timecodeSettings: settings,
            cuePointTypes: types(),
            editorMode: .cue
        )
        XCTAssertEqual(model.progress, 0.25, accuracy: 0.0001)
        XCTAssertEqual(model.lengthLabel, "02:00")
    }

    func test_progress_clampsToOneWhenPastEnd() {
        let model = MiniPlayerModel.make(
            currentTime: 200,
            duration: 120,
            item: item(),
            timecodeSettings: settings,
            cuePointTypes: types(),
            editorMode: .cue
        )
        XCTAssertEqual(model.progress, 1.0, accuracy: 0.0001)
    }

    func test_progress_zeroForZeroDuration() {
        let model = MiniPlayerModel.make(
            currentTime: 30,
            duration: 0,
            item: item(),
            timecodeSettings: settings,
            cuePointTypes: types(),
            editorMode: .cue
        )
        XCTAssertEqual(model.progress, 0)
    }

    func test_lengthLabel_formatsMinutesSeconds() {
        let model = MiniPlayerModel.make(
            currentTime: 0,
            duration: 204,
            item: item(),
            timecodeSettings: settings,
            cuePointTypes: types(),
            editorMode: .cue
        )
        XCTAssertEqual(model.lengthLabel, "03:24")
    }

    func test_empty_progressZeroAndLengthZero() {
        let model = MiniPlayerModel.make(
            currentTime: 0,
            duration: 0,
            item: nil,
            timecodeSettings: settings,
            cuePointTypes: types(),
            editorMode: .cue
        )
        XCTAssertEqual(model.progress, 0)
        XCTAssertEqual(model.lengthLabel, "00:00")
    }

    // MARK: - Show mode: GO + type filter

    func test_showMode_showsGo() {
        let model = MiniPlayerModel.make(
            currentTime: 35,
            item: item(),
            timecodeSettings: settings,
            cuePointTypes: types(),
            editorMode: .show
        )
        XCTAssertTrue(model.showsGo)
    }

    func test_showMode_typeFilter_restrictsCurrentAndNext() {
        // Filter to Amber only: at 35s the active Amber cue is #1 (Lights Up @10),
        // and the next Amber cue is #3 (Chorus @60) — cue #2 (Teal) is skipped.
        let model = MiniPlayerModel.make(
            currentTime: 35,
            item: item(),
            timecodeSettings: settings,
            cuePointTypes: types(),
            editorMode: .show,
            showGoTypeID: amberID
        )
        XCTAssertEqual(model.currentCue?.name, "Lights Up")
        XCTAssertEqual(model.currentCue?.colorHex, "#FFA94D")
        XCTAssertEqual(model.nextCue?.cue.name, "Chorus")
    }

    func test_cueMode_ignoresShowGoTypeID() {
        // Not in Show mode → the type filter must NOT apply.
        let model = MiniPlayerModel.make(
            currentTime: 35,
            item: item(),
            timecodeSettings: settings,
            cuePointTypes: types(),
            editorMode: .cue,
            showGoTypeID: amberID
        )
        XCTAssertEqual(model.currentCue?.name, "Verse 1") // unfiltered active cue
    }
}
