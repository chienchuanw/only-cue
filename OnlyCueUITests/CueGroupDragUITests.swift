import XCTest

/// BDD-style scenarios for direct-manipulation drag of cue markers on the
/// main-pane waveform.
///
/// Spec: `docs/superpowers/specs/2026-05-14-marker-drag-and-group-drag-design.md`
///
/// **Status:** Scenarios are scaffolded but currently skipped. End-to-end UI
/// coverage requires (a) a launch-argument seed mechanism in `OnlyCueApp` that
/// constructs a `CueListDocument` with pre-positioned cues *and* a non-zero
/// `loadedDuration` on the active media item, and (b) a way to bypass the real
/// `AVPlayer` media-load path so `WaveformContainer` will render the markers
/// overlay. Both are non-trivial changes to production code; until they exist,
/// the underlying command contract is covered by
/// `OnlyCueTests/CueMarkersOverlayDispatchTests` (group nudge + clamp + solo
/// retime) and the geometry by `OnlyCueTests/CueMarkersGeometryTests`
/// (`snapDeltaToBeat`).
///
/// When the seed mechanism lands, remove the `XCTSkip` calls below and verify
/// each Gherkin scenario.
final class CueGroupDragUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Scenario: Group drag shifts all selected cues rigidly
    /// Given a project with cues at 1s, 3s, 6s and all selected
    /// When the user drags the marker at 3s by +N px on the waveform
    /// Then all three cue times shift by the same Δt
    /// And the undo stack has one entry (single ⌘Z restores everything)
    func test_groupDrag_shiftsAllSelectedCuesRigidly() throws {
        throw XCTSkip("Pending --ui-test-seed=three-cues-1-3-6 seed mechanism in OnlyCueApp (see file header).")

        // Reference implementation, ready to enable once seed + media-bypass exist:
        //
        // let app = XCUIApplication()
        // app.launchArguments += ["--ui-test-seed=three-cues-1-3-6"]
        // app.launch()
        //
        // let cueList = app.outlines["cueListPane"]
        // XCTAssertTrue(cueList.waitForExistence(timeout: 5))
        // cueList.click()
        // cueList.typeKey("a", modifierFlags: .command)
        //
        // let markers = app.otherElements["cueMarkersOverlay"]
        // XCTAssertTrue(markers.waitForExistence(timeout: 5))
        // let middleMarker = markers.descendants(matching: .any).matching(
        //     NSPredicate(format: "identifier BEGINSWITH 'cueMarker-'")
        // ).element(boundBy: 1)
        // XCTAssertTrue(middleMarker.exists)
        //
        // let start = middleMarker.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.5))
        // let end = start.withOffset(.init(dx: 80, dy: 0))
        // start.press(forDuration: 0.1, thenDragTo: end)
        //
        // let rows = cueList.outlineRows
        // XCTAssertEqual(rows.count, 3)
        // let observed = (0..<3).map { idx -> TimeInterval in
        //     Self.parseSeconds(fromAccessibilityLabel: rows.element(boundBy: idx).label)
        // }
        // let deltas = zip(observed, [1.0, 3.0, 6.0]).map { $0 - $1 }
        // XCTAssertEqual(deltas[0], deltas[1], accuracy: 0.01)
        // XCTAssertEqual(deltas[1], deltas[2], accuracy: 0.01)
        // XCTAssertGreaterThan(deltas[0], 0)
        //
        // app.typeKey("z", modifierFlags: .command)
        // let restored = (0..<3).map { idx -> TimeInterval in
        //     Self.parseSeconds(fromAccessibilityLabel: rows.element(boundBy: idx).label)
        // }
        // XCTAssertEqual(restored[0], 1.0, accuracy: 0.01)
        // XCTAssertEqual(restored[1], 3.0, accuracy: 0.01)
        // XCTAssertEqual(restored[2], 6.0, accuracy: 0.01)
    }

    /// Scenario: Dragging an unselected marker replaces the selection
    /// Given cues at 1s, 3s, 6s; cues at 1s and 3s selected
    /// When the user drags the marker at 6s by +N px
    /// Then only the cue at 6s has moved
    /// And the selection is exactly { cue at moved-time }
    func test_dragUnselectedMarker_replacesSelectionAndMovesSolo() throws {
        throw XCTSkip("Pending --ui-test-seed=three-cues-1-3-6-select-first-two seed mechanism in OnlyCueApp (see file header).")

        // Reference implementation, ready to enable once seed + media-bypass exist:
        //
        // let app = XCUIApplication()
        // app.launchArguments += ["--ui-test-seed=three-cues-1-3-6-select-first-two"]
        // app.launch()
        //
        // let markers = app.otherElements["cueMarkersOverlay"]
        // XCTAssertTrue(markers.waitForExistence(timeout: 5))
        // let thirdMarker = markers.descendants(matching: .any).matching(
        //     NSPredicate(format: "identifier BEGINSWITH 'cueMarker-'")
        // ).element(boundBy: 2)
        //
        // let start = thirdMarker.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.5))
        // let end = start.withOffset(.init(dx: 40, dy: 0))
        // start.press(forDuration: 0.1, thenDragTo: end)
        //
        // let cueList = app.outlines["cueListPane"]
        // let rows = cueList.outlineRows
        // XCTAssertEqual(rows.count, 3)
        // let observed = (0..<3).map { idx -> TimeInterval in
        //     Self.parseSeconds(fromAccessibilityLabel: rows.element(boundBy: idx).label)
        // }
        // XCTAssertEqual(observed[0], 1.0, accuracy: 0.01)
        // XCTAssertEqual(observed[1], 3.0, accuracy: 0.01)
        // XCTAssertGreaterThan(observed[2], 6.0)
        //
        // let selectedRows = rows.matching(NSPredicate(format: "selected == YES"))
        // XCTAssertEqual(selectedRows.count, 1)
    }

    /// Scenario: Shift held during drag snaps to the tempo grid
    /// Given a project with a tempo grid (e.g. 120 BPM) and a cue at 1.0s
    /// When the user holds Shift and drags the marker toward the next beat
    /// Then on release the cue's time is exactly on a beat (within tolerance)
    func test_shiftDrag_snapsAnchorToNearestBeat() throws {
        throw XCTSkip("Pending --ui-test-seed mechanism + tempo-grid seed key in OnlyCueApp (see file header).")

        // Reference implementation, ready to enable once seed + media-bypass +
        // tempo-grid seed key exist:
        //
        // let app = XCUIApplication()
        // app.launchArguments += ["--ui-test-seed=one-cue-at-1s-120bpm"]
        // app.launch()
        //
        // let markers = app.otherElements["cueMarkersOverlay"]
        // XCTAssertTrue(markers.waitForExistence(timeout: 5))
        // let marker = markers.descendants(matching: .any).matching(
        //     NSPredicate(format: "identifier BEGINSWITH 'cueMarker-'")
        // ).element(boundBy: 0)
        //
        // // Hold shift across the drag.
        // XCUIElement.perform(withKeyModifiers: .shift) {
        //     let start = marker.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.5))
        //     let end = start.withOffset(.init(dx: 12, dy: 0))
        //     start.press(forDuration: 0.1, thenDragTo: end)
        // }
        //
        // let cueList = app.outlines["cueListPane"]
        // let rows = cueList.outlineRows
        // let observed = Self.parseSeconds(fromAccessibilityLabel: rows.element(boundBy: 0).label)
        // // 120 BPM beats every 0.5s; the nearest beat to ~1.0s + small Δ is 1.5s.
        // XCTAssertEqual(observed.truncatingRemainder(dividingBy: 0.5), 0, accuracy: 0.05)
    }

    // MARK: - Helpers

    /// `CueRowView` exposes cue time via the row's accessibility label, derived
    /// from `TimeFormat.hms` (`HH:MM:SS.mmm`). Extract the seconds component.
    /// Adjust this regex if `CueRowView`'s label construction changes.
    private static func parseSeconds(fromAccessibilityLabel label: String) -> TimeInterval {
        let pattern = #"(\d+):(\d+):(\d+(?:\.\d+)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: label, range: NSRange(label.startIndex..., in: label)),
              let hRange = Range(match.range(at: 1), in: label),
              let mRange = Range(match.range(at: 2), in: label),
              let sRange = Range(match.range(at: 3), in: label),
              let hours = Double(label[hRange]),
              let minutes = Double(label[mRange]),
              let seconds = Double(label[sRange]) else {
            return .nan
        }
        return hours * 3600 + minutes * 60 + seconds
    }
}
