import Foundation

/// Named `@AppStorage` keys for the OSC server's user preferences, so the
/// settings pane and the per-document server host don't duplicate bare string
/// literals. Mirrors the `FirstLaunchFlag.key` / `NotesOverlayPreferences.storageKey`
/// convention elsewhere in the codebase.
enum OSCServerSettings {
    static let enabledKey = "oscServerEnabled"
    static let portKey = "oscServerPort"

    /// Default listen port surfaced as the `@AppStorage` default value.
    static let defaultPort = Int(OSCServer.defaultPort)
}
