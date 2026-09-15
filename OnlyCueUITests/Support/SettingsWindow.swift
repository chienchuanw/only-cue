import AppKit
import XCTest

/// Helpers for working with the macOS Settings window, whose title tracks the
/// selected pane (`TabView` behaviour) so it can't be matched by a fixed name.
///
/// Lived at the bottom of `OSCSettingsScreenshotTests.swift` until #819 made it
/// the shared fix site for the ⌘, race; seven suites already depended on it, so
/// it moved here rather than staying inside one suite's file.
enum SettingsWindowFinder {

    /// Foreground the app, press ⌘, and wait for a window to appear above
    /// `baseline` — **retrying the keystroke**, not just extending the wait.
    ///
    /// Why a retry and not a longer timeout (#819): the single-shot form this
    /// replaces (`activateRobustly` + one `typeKey` + a 15 s wait) failed once
    /// in 25 local runs of `GeneralSettingsScreenshotTests`. Twenty instrumented
    /// reruns could not reproduce it — every one showed the activation returning
    /// true, `com.chienchuanw.OnlyCue` frontmost, and the window count going
    /// 1 → 2 — so the mechanism is unproven and this is handling, not a
    /// root-cause fix. What the evidence does rule out is the app merely being
    /// slow: 15 s of polling is not a budget more seconds would rescue. That
    /// leaves the keystroke itself not landing — delivered a hair before the app
    /// became key, or swallowed by something transient on the runner's session —
    /// and the only handling for a lost keystroke is to send it again.
    ///
    /// Pressing ⌘, when Settings is already open is harmless (it is a single
    /// window scene, so the second press just refocuses it), but a retry only
    /// happens while the window count has not moved anyway.
    ///
    /// On each failed attempt the app's state is printed, so a failure in CI
    /// says what the session looked like instead of leaving it to be
    /// reconstructed afterwards.
    @discardableResult
    static func open(
        in app: XCUIApplication,
        above baseline: Int,
        attempts: Int = 3,
        timeoutPerAttempt: TimeInterval = 10
    ) -> Bool {
        for attempt in 1...max(1, attempts) {
            Foregrounding.activateRobustly(app)
            app.typeKey(",", modifierFlags: .command)
            if waitForNewWindow(in: app, above: baseline, timeout: timeoutPerAttempt) {
                return true
            }
            print("[settings] ⌘, attempt \(attempt)/\(attempts) opened no window above \(baseline) — \(diagnostics(for: app))")
        }
        return false
    }

    /// Polls until the app has more than `baseline` windows (the Settings window
    /// opened on top of the document window), or the timeout elapses.
    static func waitForNewWindow(in app: XCUIApplication, above baseline: Int, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if app.windows.count > baseline { return true }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return app.windows.count > baseline
    }

    /// The Settings window by one of the titles its panes produce, or `nil`
    /// (in which case callers screenshot the whole screen instead).
    static func window(in app: XCUIApplication) -> XCUIElement? {
        for title in ["OnlyCue Settings", "Settings", "General", "Audio", "Keyboard", "OSC", "MIDI", "grandMA2"] {
            let window = app.windows[title]
            if window.exists { return window }
        }
        return nil
    }

    private static func diagnostics(for app: XCUIApplication) -> String {
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "none"
        let titles = app.windows.allElementsBoundByIndex.prefix(5).map(\.title)
        return "frontmost=\(frontmost) windows=\(app.windows.count) titles=\(titles)"
    }
}
