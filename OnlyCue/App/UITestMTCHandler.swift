#if DEBUG
import Foundation

/// `#if DEBUG`-only launch handler that makes MTC output **hermetic** for UI
/// tests, the twin of `UITestLTCHandler`. Any `--ui-test*` launch runs MTC
/// settings fully in memory (persistence suppressed) so a test can neither read
/// a polluted `mtcOutput.v1` nor write one for the next run / the user's real app:
///
/// - `--ui-test-mtc-enabled` → start enabled, with no destination selected, so
///   the transport pill renders without any MIDI hardware being present.
/// - any other `--ui-test*` launch → start at the disabled default, so tests
///   that assume "MTC off by default" are deterministic regardless of whatever
///   `mtcOutput.v1` an earlier (possibly aborted) run left behind.
///
/// Production builds skip this file.
enum UITestMTCHandler {

    private static let enableArgument = "--ui-test-mtc-enabled"

    /// Marker the CI workflow `touch`es for the duration of the UI-tests step,
    /// so plain-`launch()` UI tests still run MTC hermetically on the runner.
    /// Same marker `UITestLTCHandler` watches.
    private static let ciMarkerPath = "/tmp/.onlycue-ci-active"

    @MainActor
    static func applyIfRequested() {
        let arguments = CommandLine.arguments
        let isUITestLaunch = arguments.contains { $0.hasPrefix("--ui-test") }
            || FileManager.default.fileExists(atPath: ciMarkerPath)
        guard isUITestLaunch else { return }
        // `applyEphemeralForUITests` suppresses persistence on `shared` only —
        // scoped per-instance so it never leaks into unit tests (#697).
        let settings = arguments.contains(enableArgument)
            ? MTCOutputSettings(isEnabled: true, destinationUID: nil)
            : .default
        MTCOutputStore.shared.applyEphemeralForUITests(settings)
    }
}
#endif
