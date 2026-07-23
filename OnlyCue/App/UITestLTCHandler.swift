#if DEBUG
import Foundation

/// `#if DEBUG`-only launch handler that makes LTC routing **hermetic** for UI
/// tests. Any `--ui-test*` launch runs LTC routing fully in memory (persistence
/// suppressed) so a test can neither read a polluted `ltcRouting.v1` nor write
/// one for the next run / the user's real app:
///
/// - `--ui-test-ltc-enabled` → start enabled (4-channel LTC / Track L / Track R
///   / Silent), e.g. for the Audio-settings screenshot capture.
/// - any other `--ui-test*` launch → start at the disabled default, so tests
///   that assume "LTC off by default" are deterministic regardless of whatever
///   `ltcRouting.v1` an earlier (possibly aborted) run left behind (#599).
///
/// Production builds skip this file.
enum UITestLTCHandler {

    private static let enableArgument = "--ui-test-ltc-enabled"
    private static let enabledSettings = LTCRoutingSettings(
        isEnabled: true,
        deviceUID: nil,
        channelRoles: [.ltc, .trackLeft, .trackRight, .silent]
    )

    /// Marker the CI workflow `touch`es for the duration of the UI-tests step
    /// (`CIRuntime.isSelfHostedRunner`). Lets plain-`launch()` UI tests (no
    /// `--ui-test*` arg) still run LTC hermetically on the runner.
    private static let ciMarkerPath = "/tmp/.onlycue-ci-active"

    @MainActor
    static func applyIfRequested() {
        let arguments = CommandLine.arguments
        let isUITestLaunch = arguments.contains { $0.hasPrefix("--ui-test") }
            || FileManager.default.fileExists(atPath: ciMarkerPath)
        guard isUITestLaunch else { return }
        // Run the whole session in memory so neither this handler nor the
        // settings pane's on-appear reconcile touches the persisted default.
        // `applyEphemeralForUITests` suppresses persistence on `shared` only —
        // scoped per-instance so it never leaks into unit tests (#697).
        let settings = arguments.contains(enableArgument) ? enabledSettings : .default
        LTCRoutingStore.shared.applyEphemeralForUITests(settings)
    }
}
#endif
