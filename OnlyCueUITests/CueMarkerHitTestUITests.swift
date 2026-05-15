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
    /// Then exactly that marker carries the `isSelected` accessibility trait.
    ///
    /// `CueMarkerView` adds `.accessibilityAddTraits(.isSelected)` when its
    /// `isSelected` flag is set, which is the same flag the parent overlay
    /// derives from `selectedCueIDs`. So a green assertion here proves the
    /// click reached `CueMarkerView`'s drag-gesture (`onSelectCue` was
    /// dispatched) — the exact behaviour broken before this fix, when the
    /// click was absorbed by the seek surface above.
    func test_clickOnMarker_selectsTheUnderlyingCue() throws {
        let app = launchWithSeed(.threeCuesAt1And3And6)
        defer { app.terminate() }

        var markers = try CueGroupDragUITests.waitForMarkers(in: app, count: 3)

        // Sanity: nothing selected at launch.
        XCTAssertEqual(markers.filter { $0.isSelected }.count, 0,
                       "No marker should carry the isSelected trait at launch.")

        // Click the middle marker (cue at 3s).
        let middleID = markers[1].identifier
        let middle = CueGroupDragUITests.markerHitCoordinate(markers[1])
        middle.click()
        Thread.sleep(forTimeInterval: 0.4)

        // Re-query — XCUIElement caches don't refresh after a state change.
        markers = try CueGroupDragUITests.waitForMarkers(in: app, count: 3)
        let selected = markers.filter { $0.isSelected }
        XCTAssertEqual(selected.count, 1,
                       "Clicking a marker should leave exactly one marker carrying the isSelected trait.")
        XCTAssertEqual(selected.first?.identifier, middleID,
                       "The selected marker should be the one that was clicked.")
    }

    private func launchWithSeed(_ key: SeedKey) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [key.launchArgument]
        app.launch()
        return app
    }
}
