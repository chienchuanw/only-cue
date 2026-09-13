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
/// Trigger (same shape as `UITestLTCHandler`): any `--ui-test*` launch argument.
/// Every UI-test launch carries one — the base `OnlyCueUITestCase` always adds
/// `--ui-test-reset`, and each manual screenshot launch passes a `--ui-test*`
/// argument of its own — so the decision rests entirely on the arguments and no
/// longer consults a CI marker file (#792).
///
/// Ordering: this MUST run before the other `#if DEBUG` UI-test handlers in
/// `OnlyCueApp.init` so they re-establish their deterministic state on top of the
/// clean slate (the first-launch flag, the appearance override, the LTC routing).
///
/// Production builds skip this file entirely (`#if DEBUG`).
enum UITestDefaultsResetHandler {

    /// True when defaults should be wiped: any `--ui-test*` argument is present
    /// (covers the explicit `--ui-test-reset` the base test case adds and every
    /// seeded launch). Pure so the precedence is unit-tested without launching
    /// the app.
    static func isResetRequested(arguments: [String]) -> Bool {
        arguments.contains { $0.hasPrefix("--ui-test") }
    }

    /// Called at app launch, before the other UI-test handlers. Wipes the app's
    /// persistent `UserDefaults` domain when a reset is requested.
    @MainActor
    static func applyIfRequested() {
        guard isResetRequested(arguments: CommandLine.arguments) else { return }
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        UserDefaults.standard.removePersistentDomain(forName: bundleID)
    }
}
#endif
