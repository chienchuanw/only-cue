#if DEBUG
import AppKit

/// `#if DEBUG`-only launch handler that pins the app to a fixed appearance
/// regardless of the host's System Settings → Appearance choice. Trigger:
/// pass `--ui-test-appearance=dark` (or `light`) as a launch argument.
///
/// XCUITest cannot toggle the system-wide appearance, so a dark-mode visual
/// baseline would otherwise depend on whatever the developer's machine is set
/// to. Pinning the appearance from a launch argument makes the dark-mode
/// screenshot test deterministic.
///
/// Production builds skip this file entirely (`#if DEBUG`).
enum UITestAppearanceHandler {

    private static let argumentPrefix = "--ui-test-appearance="

    /// Called at app launch. If an appearance arg is present and recognized,
    /// pins `NSApp.appearance`; otherwise no-ops so the app follows System
    /// Settings as usual.
    @MainActor
    static func applyAppearanceOverrideIfRequested() {
        guard let name = appearanceName(from: CommandLine.arguments) else { return }
        NSApp.appearance = NSAppearance(named: name)
    }

    /// Parses the launch arguments for `--ui-test-appearance=<value>` and maps
    /// the value to an `NSAppearance.Name`. Returns `nil` when the argument is
    /// absent or the value is unrecognized. Pure so it can be unit-tested
    /// without launching the app.
    static func appearanceName(from arguments: [String]) -> NSAppearance.Name? {
        for arg in arguments where arg.hasPrefix(argumentPrefix) {
            switch String(arg.dropFirst(argumentPrefix.count)) {
            case "dark": return .darkAqua
            case "light": return .aqua
            default: return nil
            }
        }
        return nil
    }
}
#endif
