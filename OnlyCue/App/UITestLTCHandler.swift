#if DEBUG
import Foundation

/// `#if DEBUG`-only launch handler: pass `--ui-test-ltc-enabled` to start the
/// session with LTC routing enabled (a 4-channel LTC / Track L / Track R /
/// Silent assignment), applied **in memory only**. It never writes the
/// persisted `ltcRouting.v1` default, so it leaves no side effect for other
/// tests or the user's app — unlike clicking the toggle, which would persist.
///
/// This lets the Audio settings screenshot test capture the configured pane
/// (device + channel cards) deterministically. Production builds skip this file.
enum UITestLTCHandler {

    private static let argument = "--ui-test-ltc-enabled"

    @MainActor
    static func applyIfRequested() {
        guard CommandLine.arguments.contains(argument) else { return }
        // Run the whole session in memory so the pane's own on-appear
        // reconcile can't write the persisted default.
        LTCRoutingStore.suppressPersistenceForUITests = true
        LTCRoutingStore.shared.applyEphemeralForUITests(
            LTCRoutingSettings(
                isEnabled: true,
                deviceUID: nil,
                channelRoles: [.ltc, .trackLeft, .trackRight, .silent]
            )
        )
    }
}
#endif
