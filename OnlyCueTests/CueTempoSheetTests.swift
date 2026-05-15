import XCTest
import SwiftUI
@testable import OnlyCue

@MainActor
final class CueTempoSheetTests: XCTestCase {

    // MARK: - CueTempoCommit (the pure-Swift logic powering Save)

    func test_resolve_parsesBothDrafts() {
        let result = CueTempoCommit.resolve(
            bpmDraft: "120",
            beatsPerBarDraft: "3",
            initialBPM: nil,
            initialBeatsPerBar: nil
        )
        XCTAssertEqual(result.bpm, 120)
        XCTAssertEqual(result.beatsPerBar, 3)
    }

    func test_resolve_emptyBPM_clearsBothValues() {
        let result = CueTempoCommit.resolve(
            bpmDraft: "",
            beatsPerBarDraft: "4",
            initialBPM: 120,
            initialBeatsPerBar: 4
        )
        XCTAssertNil(result.bpm)
        XCTAssertNil(result.beatsPerBar)
    }

    func test_resolve_invalidBPM_revertsToInitial() {
        let result = CueTempoCommit.resolve(
            bpmDraft: "not-a-number",
            beatsPerBarDraft: "4",
            initialBPM: 120,
            initialBeatsPerBar: 4
        )
        XCTAssertEqual(result.bpm, 120)
        XCTAssertEqual(result.beatsPerBar, 4)
    }

    func test_resolve_unparseableBeats_fallsBackToInitial() {
        let result = CueTempoCommit.resolve(
            bpmDraft: "100",
            beatsPerBarDraft: "x",
            initialBPM: 120,
            initialBeatsPerBar: 3
        )
        XCTAssertEqual(result.bpm, 100)
        XCTAssertEqual(result.beatsPerBar, 3)
    }

    func test_resolve_nonFiniteBPM_revertsToInitial() {
        let result = CueTempoCommit.resolve(
            bpmDraft: "inf",
            beatsPerBarDraft: "4",
            initialBPM: 120,
            initialBeatsPerBar: 4
        )
        XCTAssertEqual(result.bpm, 120)
    }

    func test_formatDetectedBPM_roundsToNearestInt() {
        XCTAssertEqual(CueTempoCommit.formatDetectedBPM(127.4), "127")
        XCTAssertEqual(CueTempoCommit.formatDetectedBPM(127.6), "128")
    }

    // MARK: - CueTempoSheet behavior

    func test_commit_initialBPMRoundtripsThroughOnSave() {
        var captured: (Double?, Int?)?
        let sheet = CueTempoSheet(
            cueLabel: "Cue 1",
            initialBPM: 120,
            initialBeatsPerBar: 4,
            onDetect: { _ in nil },
            onSave: { bpm, bpb in captured = (bpm, bpb) },
            onCancel: {}
        )
        sheet.testCommit()
        XCTAssertEqual(captured?.0, 120)
        XCTAssertEqual(captured?.1, 4)
    }

    func test_commit_nilInitial_commitsNilPair() {
        var captured: (Double?, Int?)?
        let sheet = CueTempoSheet(
            cueLabel: "Cue 1",
            initialBPM: nil,
            initialBeatsPerBar: nil,
            onDetect: { _ in nil },
            onSave: { bpm, bpb in captured = (bpm, bpb) },
            onCancel: {}
        )
        sheet.testCommit()
        XCTAssertNil(captured?.0)
        XCTAssertNil(captured?.1)
    }

    func test_cancelDoesNotInvokeOnSave() {
        var saveCalled = false
        var cancelCalled = false
        let sheet = CueTempoSheet(
            cueLabel: "Cue 1",
            initialBPM: nil,
            initialBeatsPerBar: nil,
            onDetect: { _ in nil },
            onSave: { _, _ in saveCalled = true },
            onCancel: { cancelCalled = true }
        )
        sheet.testCancel()
        XCTAssertFalse(saveCalled)
        XCTAssertTrue(cancelCalled)
    }

    func test_detectDoesNotInvokeOnSave() async {
        var saveCalled = false
        var detectCalled = false
        let sheet = CueTempoSheet(
            cueLabel: "Cue 1",
            initialBPM: nil,
            initialBeatsPerBar: nil,
            onDetect: { _ in
                detectCalled = true
                return (bpm: 128.0, message: nil)
            },
            onSave: { _, _ in saveCalled = true },
            onCancel: {}
        )
        let formatted = await sheet.testRunDetect()
        XCTAssertTrue(detectCalled)
        XCTAssertFalse(saveCalled, "Detect must populate the draft only — it must not auto-save.")
        XCTAssertEqual(formatted, "128")
    }
}
