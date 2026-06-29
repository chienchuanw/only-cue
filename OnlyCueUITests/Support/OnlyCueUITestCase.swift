import AppKit
import XCTest

/// Shared base class for OnlyCue UI tests. Centralizes the launch sequence so
/// every behavioral test:
///
/// - starts from a clean `UserDefaults` slate (`--ui-test-reset`, consumed by
///   `UITestDefaultsResetHandler`) and ignores stale window/state restoration
///   (`-ApplePersistenceIgnoreState YES`),
/// - foregrounds robustly through `Foregrounding.activateRobustly` rather than a
///   bare `app.activate()`, which loses the window-server race on the
///   self-hosted runner,
/// - kills any leftover OnlyCue process before launching and terminates its own
///   instance in teardown, so leaked instances stop feeding "peer may have been
///   unloaded" crashes in later tests.
///
/// These were the per-launch state leaks, leaked instances, and foregrounding
/// races that made the suite intermittently red and green on re-run (#603).
/// Behavioral tests subclass this and call `launchApp(seed:)`.
class OnlyCueUITestCase: XCTestCase {

    /// The app's real bundle identifier. Note: several tests historically killed
    /// stale instances using `chienchuanw.OnlyCue` (missing the `com.` prefix),
    /// which matched nothing — consolidating here fixes that silently.
    static let bundleIdentifier = "com.chienchuanw.OnlyCue"

    /// The app launched by `launchApp(...)`, terminated automatically in teardown.
    private(set) var app: XCUIApplication?

    override func setUpWithError() throws {
        continueAfterFailure = false
        // XCUIApplication occasionally attaches to an already-running instance
        // instead of forking a fresh one, leaving a stale seeded document in the
        // AX tree. Force-terminate any survivor before launching.
        for running in NSRunningApplication.runningApplications(
            withBundleIdentifier: Self.bundleIdentifier
        ) {
            running.forceTerminate()
        }
        Thread.sleep(forTimeInterval: 0.5)
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    /// Launch OnlyCue with hermetic defaults and robust foregrounding.
    ///
    /// - Parameters:
    ///   - seed: optional seed document to open at launch.
    ///   - extraArguments: additional launch arguments (e.g. appearance overrides).
    /// - Returns: the launched app, also stored in `app` for teardown.
    @discardableResult
    func launchApp(
        seed: SeedKey? = nil,
        extraArguments: [String] = []
    ) -> XCUIApplication {
        let app = XCUIApplication()
        // --ui-test-reset wipes persisted defaults to a clean slate; that resets
        // the first-launch flag to its show-the-sheet default, so suppress the
        // sheet explicitly or it covers the document under test (#603).
        app.launchArguments += [
            "--ui-test-reset",
            "--ui-test-first-launch=suppress",
            "-ApplePersistenceIgnoreState", "YES"
        ]
        if let seed {
            app.launchArguments.append(seed.launchArgument)
        }
        app.launchArguments += extraArguments
        app.launch()
        // Best-effort foreground nudge via AppKit. We deliberately do NOT call
        // XCUIApplication.activate() here: on the self-hosted runner it records a
        // hard "Failed to activate application" failure whenever the GUI session
        // can't foreground (e.g. a locked screen), and with
        // continueAfterFailure=false that aborts the test before any retry.
        // NSRunningApplication.activate is best-effort and never fails the test;
        // launch() already foregrounds in a healthy, unlocked session (#605).
        for running in NSRunningApplication.runningApplications(
            withBundleIdentifier: Self.bundleIdentifier
        ) {
            running.activate(options: [.activateAllWindows])
        }
        self.app = app
        return app
    }

    /// Waits for the seeded document window (`UITestSeedHandler` writes it as
    /// `seed-<UUID>.cuelist`). State restoration is disabled at launch, but
    /// scoping queries to this window still guards against any stray document.
    func waitForSeedWindow(in app: XCUIApplication, timeout: TimeInterval = 15) throws -> XCUIElement {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let windows = app.windows.allElementsBoundByIndex
            if let match = windows.first(where: { $0.title.hasPrefix("seed-") }) {
                return match
            }
            Thread.sleep(forTimeInterval: 0.3)
        }
        throw XCTestError(.failureWhileWaiting)
    }
}
