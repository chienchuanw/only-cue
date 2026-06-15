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

/// Seed-mechanism smoke + the #264 coordinate-tap row-click contract for the
/// main-pane waveform. The direct-manipulation drag scenarios were removed
/// (#548): XCUITest's synthesised press-and-drag never reaches SwiftUI's
/// DragGesture on macOS (#273), so those tests were unconditional `XCTSkip`s.
/// The drag/snap logic is covered by unit tests (`CueMarkersGeometryTests`,
/// snap/nudge command tests).
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

    /// Verifies the #264 fix: cue rows can be interacted with via
    /// coordinate-based taps even though XCUITest's standard hit-test lands
    /// on the enclosing ScrollView. Before the fix, the first click line
    /// below would fail with "Unable to find hit point for ScrollView".
    func test_rowClick_succeedsViaCoordinateTap() throws {
        let app = launchWithSeed(.threeCuesAt1And3And6)
        defer { app.terminate() }

        _ = try Self.waitForMarkers(in: app, count: 3)
        let rows = Self.sortedCueRows(in: app)
        XCTAssertEqual(rows.count, 3)

        // The mere fact that `clickRow` returns without throwing a hit-test
        // error is the #264 contract. SwiftUI List's `isSelected` doesn't
        // surface reliably through the row's AX wrapper, so we don't assert
        // selection state — that's a separate concern.
        Self.clickRow(rows[0])
        Self.clickRow(rows[1])
        Self.clickRow(rows[2])
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

    /// Markers inside the SEEDED window only, de-duped by identifier and sorted
    /// by x so `[0]` is the leftmost marker. Window-scoping keeps stale
    /// state-restoration docs out; de-duping collapses the duplicate AX elements
    /// SwiftUI creates per accessibility wrapper.
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

    /// Clicks a cue row via its coordinate center, bypassing the standard
    /// hit-test that would otherwise fail with "Unable to find hit point for
    /// ScrollView" — the row's `accessibilityIdentifier` surfaces on a SwiftUI
    /// wrapper whose hit-test chain terminates at the enclosing `ScrollView`.
    static func clickRow(_ row: XCUIElement) {
        row.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.5)).click()
    }

    /// Cue rows inside the seeded window, de-duped and sorted top-to-bottom.
    static func sortedCueRows(in app: XCUIApplication) -> [XCUIElement] {
        let window = seedWindow(in: app) ?? app.windows.firstMatch
        let elements = window.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'cueRow-'")
        ).allElementsBoundByIndex
        return Self.dedupedByIdentifier(elements).sorted { $0.frame.minY < $1.frame.minY }
    }
}
