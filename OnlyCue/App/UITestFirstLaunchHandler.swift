#if DEBUG
import Foundation

/// `#if DEBUG`-only launch handler that forces the first-launch sheet to appear
/// regardless of the `didShowFirstLaunchNudge` `@AppStorage` flag's saved value.
/// Trigger: pass `--ui-test-first-launch=force` as a launch argument.
///
/// The first-launch sheet is normally a one-shot nudge that only opens until the
/// user dismisses it; once dismissed, the AppStorage flag is true and the sheet
/// never re-renders. That makes the sheet impossible to capture cleanly from a
/// UI-test runner whose user-defaults are not reset across runs.
///
/// This handler clears the AppStorage flag at launch when the force argument is
/// present, so the sheet renders on the next document-window appearance. The
/// `--ui-test-first-launch=suppress` value is reserved (and explicitly returns
/// `false` from `shouldForceFirstLaunch`) so future tests can keep the sheet
/// hidden without relying on whatever the runner's defaults happen to hold.
///
/// Production builds skip this file entirely (`#if DEBUG`).
enum UITestFirstLaunchHandler {

    private static let argumentPrefix = "--ui-test-first-launch="

    /// Called at app launch. If the force argument is present, clears the
    /// `didShowFirstLaunchNudge` flag so the sheet renders.
    @MainActor
    static func applyFirstLaunchOverrideIfRequested() {
        guard shouldForceFirstLaunch(arguments: CommandLine.arguments) else { return }
        UserDefaults.standard.set(false, forKey: FirstLaunchFlag.key)
    }

    /// Parses the launch arguments for `--ui-test-first-launch=<value>` and
    /// returns `true` only when the value is exactly `force`. Pure so it can
    /// be unit-tested without launching the app.
    static func shouldForceFirstLaunch(arguments: [String]) -> Bool {
        for arg in arguments where arg.hasPrefix(argumentPrefix) {
            return String(arg.dropFirst(argumentPrefix.count)) == "force"
        }
        return false
    }
}
#endif
