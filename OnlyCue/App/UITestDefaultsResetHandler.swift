#if DEBUG
import Foundation

/// `#if DEBUG`-only launch handler that makes every UI-test launch start from a
/// clean `UserDefaults` slate. The self-hosted runner re-uses the same machine
/// and user account across runs, so persisted defaults from an earlier (possibly
/// aborted) run leak into the next: `oscServerEnabled`/`oscServerPort`, cue-list
/// column widths (layout-geometry tests depend on them), overlay toggles,
/// `transport.countdownMode`, `keymap.v1`, the `onlycue.editorMode` scene value,
/// and so on. Those leaks make behavioral tests intermittently red and green on
/// re-run (#603).
///
/// Rather than enumerate every key — a list that silently rots as new defaults
/// are added — this wipes the whole persistent domain. Any future default is
/// reset automatically.
///
/// Trigger (same shape as `UITestLTCHandler`): any `--ui-test*` launch argument,
/// or the CI marker file the workflow `touch`es for the UI-tests step (so plain
/// `app.launch()` tests reset too).
///
/// Ordering: this MUST run before the other `#if DEBUG` UI-test handlers in
/// `OnlyCueApp.init` so they re-establish their deterministic state on top of the
/// clean slate (the first-launch flag, the appearance override, the LTC routing).
///
/// Production builds skip this file entirely (`#if DEBUG`).
enum UITestDefaultsResetHandler {

    private static let resetArgument = "--ui-test-reset"

    /// Marker the CI workflow `touch`es for the duration of the UI-tests step
    /// (`CIRuntime.isSelfHostedRunner`).
    private static let ciMarkerPath = "/tmp/.onlycue-ci-active"

    /// True when defaults should be wiped: any `--ui-test*` argument is present
    /// (covers the explicit `--ui-test-reset` the base test case adds and every
    /// seeded launch), or the CI marker exists. Pure so the precedence is
    /// unit-tested without launching the app.
    static func isResetRequested(arguments: [String], ciMarkerPresent: Bool) -> Bool {
        if ciMarkerPresent { return true }
        return arguments.contains { $0.hasPrefix("--ui-test") }
    }

    /// Called at app launch, before the other UI-test handlers. Wipes the app's
    /// persistent `UserDefaults` domain when a reset is requested.
    @MainActor
    static func applyIfRequested() {
        let ciMarkerPresent = FileManager.default.fileExists(atPath: ciMarkerPath)
        guard isResetRequested(arguments: CommandLine.arguments, ciMarkerPresent: ciMarkerPresent) else {
            return
        }
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        UserDefaults.standard.removePersistentDomain(forName: bundleID)
    }
}
#endif
