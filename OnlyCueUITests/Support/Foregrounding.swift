import AppKit
import XCTest // needed for XCUIApplication signature

/// XCUITest's `app.activate()` occasionally fails on the self-hosted macOS
/// runner with `Failed to activate application ... (current state: Running
/// Background)` — the window-server can only foreground one app at a time
/// and the test runner sometimes loses the race to whatever else is on
/// screen (lock view, screensaver waking, prior leaked process). Retrying
/// the activation while nudging it through `NSRunningApplication` clears the
/// race in practice.
///
/// Tests should call `activateRobustly(app)` instead of `app.activate()`.
enum Foregrounding {

    /// Try XCUITest's activate up to `attempts` times. After each failure
    /// (detected by querying the foreground bundle id), nudge the app via
    /// `NSRunningApplication.activate(options:)` then wait briefly. Returns
    /// true if the app reaches foreground, false if all attempts fail.
    @discardableResult
    static func activateRobustly(
        _ app: XCUIApplication,
        attempts: Int = 5,
        delaySeconds: TimeInterval = 0.5
    ) -> Bool {
        for _ in 0..<attempts {
            app.activate()
            if isForeground(bundleIdentifier: "com.chienchuanw.OnlyCue") {
                return true
            }
            for running in NSRunningApplication.runningApplications(
                withBundleIdentifier: "com.chienchuanw.OnlyCue"
            ) {
                running.activate(options: [.activateAllWindows])
            }
            Thread.sleep(forTimeInterval: delaySeconds)
            if isForeground(bundleIdentifier: "com.chienchuanw.OnlyCue") {
                return true
            }
        }
        return false
    }

    private static func isForeground(bundleIdentifier: String) -> Bool {
        guard let active = NSWorkspace.shared.frontmostApplication else { return false }
        return active.bundleIdentifier == bundleIdentifier
    }
}

/// Detects whether the test process is running inside the project's
/// self-hosted CI runner. Used to scope `XCTSkipIf` guards around tests
/// that are known to flake on the runner's degraded XCUITest stack but
/// pass reliably during local development.
///
/// Detection mechanism: the workflow writes a marker file at a known
/// path before invoking `xcodebuild test`, then deletes it after. The
/// test process reads the path via `FileManager` — which works through
/// the macOS test-runner sandbox unlike environment variables.
/// Hostname-based detection is unreliable because the runner Mac is
/// the maintainer's primary dev machine, so both contexts share a host.
enum CIRuntime {
    /// Path of the marker file the CI workflow writes before
    /// `xcodebuild test` and removes after the job. Lives under the
    /// runner user's home so it's reachable through the XCUITest
    /// sandbox without granting any extra entitlements.
    static let markerPath = NSHomeDirectory() + "/.onlycue-ci-active"

    /// True when the CI workflow's marker file exists, i.e. tests are
    /// running under GitHub Actions on the self-hosted runner.
    static var isSelfHostedRunner: Bool {
        FileManager.default.fileExists(atPath: markerPath)
    }

    /// Backwards-compatible alias retained so existing `XCTSkipIf` call
    /// sites keep working. The semantic is the same — "skip this test on
    /// CI".
    static var isGitHubActions: Bool { isSelfHostedRunner }
}
