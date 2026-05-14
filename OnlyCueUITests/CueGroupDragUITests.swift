import AppKit
import XCTest

/// Thin AppKit wrapper because the test target can't import OnlyCue's
/// internals; we need to enumerate running OnlyCue instances to kill stale
/// ones before each test.
enum NSRunningApplicationFinder {
    static func runningOnlyCueApps() -> [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.chienchuanw.OnlyCue")
    }
}

/// BDD-style scenarios for direct-manipulation drag of cue markers on the
/// main-pane waveform. Spec: `docs/superpowers/specs/2026-05-14-marker-drag-and-group-drag-design.md`.
///
/// The seed mechanism is described in `docs/superpowers/specs/2026-05-14-ui-test-seed-mechanism-design.md`.
final class CueGroupDragUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        // Kill any leftover OnlyCue process from a prior test — XCUIApplication
        // sometimes attaches to the running instance instead of forking a
        // fresh one, which can leave a stale seeded document in the AX tree.
        for app in NSRunningApplicationFinder.runningOnlyCueApps() {
            app.forceTerminate()
        }
        Thread.sleep(forTimeInterval: 0.5)
    }

    // MARK: - Smoke

    /// Verifies the launch-argument → seed-handler → DocumentGroup open path
    /// opens a seeded document and `cueMarkersOverlay` becomes visible. If this
    /// is red, none of the scenarios below can pass — debug here first.
    func test_seedMechanism_opensDocumentAndRendersMarkers() throws {
        let app = launchWithSeed(.threeCuesAt1And3And6)
        defer { app.terminate() }

        let overlay = Self.markersOverlay(in: app)
        XCTAssertTrue(
            overlay.waitForExistence(timeout: 15),
            "cueMarkersOverlay should appear after the seed handler opens a document. " +
            "Check seed key, bookmark resolution, and DocumentGroup open path."
        )
        // Give AVPlayer + waveform layout a moment to settle so marker views
        // mount before we query.
        Thread.sleep(forTimeInterval: 2)

        let markerElements = Self.sortedMarkers(in: app)
        XCTAssertEqual(markerElements.count, 3, "Seeded document should render exactly three markers (unique by id).")
    }

    // MARK: - Scenarios

    /// Scenario: Group drag shifts all selected cues rigidly
    /// Given a project with cues at 1s, 3s, 6s and all selected
    /// When the user drags the marker at 3s by +N px on the waveform
    /// Then all three cue times shift by the same Δt
    /// And the undo stack has one entry (single ⌘Z restores everything)
    func test_groupDrag_shiftsAllSelectedCuesRigidly() throws {
        throw XCTSkip(
            "Pending follow-up: cueRow elements are nested in an unhittable ScrollView in the AX tree, " +
            "so XCUITest can't click rows to build the selection. " +
            "Underlying behavior is covered by CueMarkersOverlayDispatchTests + CueMarkersGeometryTests."
        )
        let app = launchWithSeed(.threeCuesAt1And3And6)
        defer { app.terminate() }

        let markers = try Self.waitForMarkers(in: app, count: 3)
        let rows = Self.sortedCueRows(in: app)
        XCTAssertEqual(rows.count, 3)

        // ⌘A on the first row to select all three cues.
        rows[0].click()
        rows[0].typeKey("a", modifierFlags: .command)

        let start = markers[1].coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.5))
        let end = start.withOffset(.init(dx: 80, dy: 0))
        start.press(forDuration: 0.1, thenDragTo: end)

        let observed = Self.cueTimes(rows: rows)
        let deltas = zip(observed, [1.0, 3.0, 6.0]).map { $0 - $1 }
        XCTAssertEqual(deltas[0], deltas[1], accuracy: 0.05, "All three cues should shift by the same Δt.")
        XCTAssertEqual(deltas[1], deltas[2], accuracy: 0.05)
        XCTAssertGreaterThan(deltas[0], 0)

        app.typeKey("z", modifierFlags: .command)
        let restored = Self.cueTimes(rows: rows)
        XCTAssertEqual(restored[0], 1.0, accuracy: 0.05, "Single undo should restore original times.")
        XCTAssertEqual(restored[1], 3.0, accuracy: 0.05)
        XCTAssertEqual(restored[2], 6.0, accuracy: 0.05)
    }

    /// Scenario: Dragging an unselected marker replaces the selection
    /// Given cues at 1s, 3s, 6s; cues at 1s and 3s selected
    /// When the user drags the marker at 6s by +N px
    /// Then only the cue at 6s has moved
    /// And the selection is exactly { cue at moved-time }
    func test_dragUnselectedMarker_replacesSelectionAndMovesSolo() throws {
        throw XCTSkip(
            "Pending follow-up: see test_groupDrag_shiftsAllSelectedCuesRigidly " +
            "for the same AX/ScrollView blocker."
        )
        let app = launchWithSeed(.threeCuesAt1And3And6)
        defer { app.terminate() }

        let markers = try Self.waitForMarkers(in: app, count: 3)
        let rows = Self.sortedCueRows(in: app)
        XCTAssertEqual(rows.count, 3)

        // Build the multi-selection: click row 0, ⌘-click row 1.
        rows[0].click()
        XCUIElement.perform(withKeyModifiers: .command) {
            rows[1].click()
        }

        let start = markers[2].coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.5))
        let end = start.withOffset(.init(dx: 40, dy: 0))
        start.press(forDuration: 0.1, thenDragTo: end)

        let observed = Self.cueTimes(rows: rows)
        XCTAssertEqual(observed[0], 1.0, accuracy: 0.05, "First cue should not have moved.")
        XCTAssertEqual(observed[1], 3.0, accuracy: 0.05, "Second cue should not have moved.")
        XCTAssertGreaterThan(observed[2], 6.0, "Third cue should have moved right.")

        let selectedCount = rows.filter { $0.isSelected }.count
        XCTAssertEqual(selectedCount, 1, "Dragging an unselected marker should collapse the selection to that cue.")
    }

    /// Scenario: Shift held during drag snaps to the tempo grid
    /// Given a project with a 120 BPM tempo grid (beats every 0.5s) and a cue at 1.0s
    /// When the user holds Shift and drags the marker by a small amount
    /// Then on release the cue's time is exactly on a beat (within tolerance)
    func test_shiftDrag_snapsAnchorToNearestBeat() throws {
        throw XCTSkip(
            "Pending follow-up: see test_groupDrag_shiftsAllSelectedCuesRigidly " +
            "for the same AX/ScrollView blocker."
        )
        let app = launchWithSeed(.threeCuesAt1And3And6With120BPM)
        defer { app.terminate() }

        // The 120 BPM seed inserts a tempo cue at 0s, so target the cue
        // originally at 1.0s — second row, second marker after sorting by x.
        let markers = try Self.waitForMarkers(in: app, count: 4)
        let rows = Self.sortedCueRows(in: app)
        XCTAssertEqual(rows.count, 4)
        let targetIndex = 1
        let originalTime: TimeInterval = 1.0

        XCUIElement.perform(withKeyModifiers: .shift) {
            let start = markers[targetIndex].coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.5))
            let end = start.withOffset(.init(dx: 30, dy: 0))
            start.press(forDuration: 0.1, thenDragTo: end)
        }

        let observed = Self.cueTimes(rows: rows)[targetIndex]
        XCTAssertNotEqual(observed, originalTime, "Drag should have moved the cue.")
        // 120 BPM → beats every 0.5s. The snapped time must lie exactly on a
        // half-second boundary.
        let beatRemainder = (observed * 2).rounded() / 2 - observed
        XCTAssertEqual(beatRemainder, 0, accuracy: 0.02, "Shift-drag should snap the cue to the nearest beat.")
    }

    // MARK: - Helpers

    /// Launches the app with the seed launch argument. The `#if DEBUG`
    /// `UITestSeedHandler` in `OnlyCueApp` does the actual document
    /// construction in the (unsandboxed) app process — see
    /// `OnlyCue/App/UITestSeedHandler.swift` for the rationale on why this
    /// indirection is necessary.
    private func launchWithSeed(_ key: SeedKey) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [key.launchArgument]
        app.launch()
        return app
    }

    /// Type-agnostic identifier lookup. `.accessibilityElement(children: .contain)`
    /// on the overlay changed its XCUIElement.ElementType away from `.other`, so
    /// `app.otherElements["cueMarkersOverlay"]` no longer matches. Querying
    /// `descendants(matching: .any)` filtered by identifier handles either case.
    static func markersOverlay(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: "cueMarkersOverlay")
            .firstMatch
    }

    /// Returns the unique cueMarker identifiers visible in the AX tree, sorted
    /// by their visual x-coordinate so `[0]` is the leftmost marker.
    /// Filtering by unique identifier de-dups XCUITest's tendency to return
    /// the same marker twice (once for the SwiftUI accessibility wrapper, once
    /// for the underlying NSAccessibilityElement).
    /// Markers inside the SEEDED window only. Scoping by window keeps stale
    /// state-restoration docs (macOS reopens recent .cuelist files at launch)
    /// out of the result, and de-duping by identifier collapses the duplicate
    /// AX elements SwiftUI creates per accessibility wrapper.
    static func sortedMarkers(in app: XCUIApplication) -> [XCUIElement] {
        let window = seedWindow(in: app) ?? app.windows.firstMatch
        let elements = window.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'cueMarker-'")
        ).allElementsBoundByIndex
        return Self.dedupedByIdentifier(elements).sorted { $0.frame.minX < $1.frame.minX }
    }

    /// SwiftUI publishes each accessibility-identified view through two AX
    /// nodes (the SwiftUI wrapper and the underlying NSAccessibilityElement),
    /// so XCUITest queries return duplicates. Keep the first occurrence per id.
    static func dedupedByIdentifier(_ elements: [XCUIElement]) -> [XCUIElement] {
        var seen = Set<String>()
        var unique: [XCUIElement] = []
        for el in elements where !el.identifier.isEmpty && seen.insert(el.identifier).inserted {
            unique.append(el)
        }
        return unique
    }

    /// The seed window's title starts with `seed-` because `UITestSeedHandler`
    /// writes its `.cuelist` to `seed-<UUID>.cuelist`.
    static func seedWindow(in app: XCUIApplication) -> XCUIElement? {
        let windows = app.windows.allElementsBoundByIndex
        return windows.first { $0.title.hasPrefix("seed-") }
    }

    /// Waits for `count` markers to appear and returns them sorted by x.
    /// Throws if they never appear within the timeout.
    static func waitForMarkers(in app: XCUIApplication, count: Int, timeout: TimeInterval = 15) throws -> [XCUIElement] {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let markers = sortedMarkers(in: app)
            if markers.count >= count { return Array(markers.prefix(count)) }
            Thread.sleep(forTimeInterval: 0.3)
        }
        throw XCTestError(.failureWhileWaiting)
    }

    /// Cue rows sorted by their x-coordinate (left-to-right inside the cue list).
    /// Same de-dup approach as `sortedMarkers`.
    static func sortedCueRows(in app: XCUIApplication) -> [XCUIElement] {
        let window = seedWindow(in: app) ?? app.windows.firstMatch
        let elements = window.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'cueRow-'")
        ).allElementsBoundByIndex
        return Self.dedupedByIdentifier(elements).sorted { $0.frame.minY < $1.frame.minY }
    }

    /// Reads the cue time off each row's `cueTime-<id>` Text — its label is the
    /// `TimeFormat.hms(cue.time)` formatted string `H:MM:SS.mmm`.
    static func cueTimes(rows: [XCUIElement]) -> [TimeInterval] {
        rows.map { row in
            let id = String(row.identifier.dropFirst("cueRow-".count))
            let timeLabel = row.descendants(matching: .any)
                .matching(identifier: "cueTime-\(id)")
                .firstMatch.label
            return parseSeconds(fromAccessibilityLabel: timeLabel)
        }
    }

    /// `CueRowView` exposes cue time via the row's accessibility label, derived
    /// from `TimeFormat.hms` (`HH:MM:SS.mmm`). Extract the seconds component.
    /// Adjust this regex if the row label construction changes.
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
