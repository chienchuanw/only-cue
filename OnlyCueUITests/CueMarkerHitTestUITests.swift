import AppKit
import XCTest

/// BDD smoke proving cue markers are reachable to pointer hit-tests.
/// Spec: `docs/superpowers/specs/2026-05-15-waveform-cue-marker-hit-test-fix-design.md`.
///
/// Before the fix, every click in the waveform area landed on the
/// full-bleed `waveformSeekSurface` rendered above the markers, so the
/// click was treated as a seek and no cue was ever selected. After the
/// fix the seek surface sits below `cueMarkersOverlay`, so a click on a
/// marker reaches `CueMarkerView` and dispatches `onSelectCue`.
final class CueMarkerHitTestUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        for app in NSRunningApplicationFinder.runningOnlyCueApps() {
            app.forceTerminate()
        }
        Thread.sleep(forTimeInterval: 0.5)
    }

    /// Given a seeded document with cues at 1s, 3s, 6s,
    /// When the user clicks the marker for the cue at 3s,
    /// Then the row for that cue becomes the only selected row.
    func test_clickOnMarker_selectsTheUnderlyingCue() throws {
        let app = launchWithSeed(.threeCuesAt1And3And6)
        defer { app.terminate() }

        let markers = try CueGroupDragUITests.waitForMarkers(in: app, count: 3)
        let rows = CueGroupDragUITests.sortedCueRows(in: app)
        XCTAssertEqual(rows.count, 3, "Seed should produce three cue rows.")

        // Sanity: nothing selected at launch.
        XCTAssertEqual(rows.filter { $0.isSelected }.count, 0,
                       "No cue should be selected before the click.")

        // Click the middle marker (cue at 3s).
        let middle = CueGroupDragUITests.markerHitCoordinate(markers[1])
        middle.click()
        Thread.sleep(forTimeInterval: 0.4)

        let selected = rows.filter { $0.isSelected }
        XCTAssertEqual(selected.count, 1,
                       "Clicking a marker should select exactly one cue.")
        XCTAssertEqual(selected.first?.identifier,
                       rows[1].identifier,
                       "The selected cue should be the one whose marker was clicked.")
    }

    private func launchWithSeed(_ key: SeedKey) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [key.launchArgument]
        app.launch()
        return app
    }
}
