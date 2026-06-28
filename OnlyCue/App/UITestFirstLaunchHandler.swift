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
/// `--ui-test-first-launch=suppress` value (which the UI-test base case passes
/// on every launch) keeps the sheet hidden regardless of the saved flag — vital
/// now that `UITestDefaultsResetHandler` wipes the persisted flag to its
/// show-the-sheet default before this runs (#603); a seeded launch is suppressed
/// the same way (#476).
///
/// Production builds skip this file entirely (`#if DEBUG`).
enum UITestFirstLaunchHandler {

    private static let argumentPrefix = "--ui-test-first-launch="

    private static let seedPrefix = "--ui-test-seed="

    /// Called at app launch. Forces the sheet to render when `=force` is set;
    /// otherwise suppresses it for any seeded or explicitly `=suppress`ed launch
    /// so the welcome sheet never overlays a deterministic test (#476, #603).
    @MainActor
    static func applyFirstLaunchOverrideIfRequested() {
        let arguments = CommandLine.arguments
        if shouldForceFirstLaunch(arguments: arguments) {
            UserDefaults.standard.set(false, forKey: FirstLaunchFlag.key)
        } else if shouldSuppress(arguments: arguments) {
            UserDefaults.standard.set(true, forKey: FirstLaunchFlag.key)
        }
    }

    /// True when the first-launch sheet should be hidden for this launch: an
    /// explicit `--ui-test-first-launch=suppress` (passed by the UI-test base
    /// case on every launch) or any seeded launch — unless `=force` explicitly
    /// asked for the sheet. Pure so the precedence is unit-tested without
    /// launching the app.
    static func shouldSuppress(arguments: [String]) -> Bool {
        guard !shouldForceFirstLaunch(arguments: arguments) else { return false }
        if arguments.contains(argumentPrefix + "suppress") { return true }
        return arguments.contains { $0.hasPrefix(seedPrefix) }
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

    /// True when a `--ui-test-seed=` is present and the sheet was not explicitly
    /// forced — seeded captures should never show the first-launch sheet. Pure
    /// so the precedence is unit-tested without launching the app.
    static func shouldSuppressForSeed(arguments: [String]) -> Bool {
        let hasSeed = arguments.contains { $0.hasPrefix(seedPrefix) }
        return hasSeed && !shouldForceFirstLaunch(arguments: arguments)
    }
}
#endif
