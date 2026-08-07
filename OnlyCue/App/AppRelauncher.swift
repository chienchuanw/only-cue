import AppKit

/// Relaunches OnlyCue. Used by the language picker, whose change only takes
/// effect once macOS re-reads `AppleLanguages` at launch. Starts a fresh
/// instance via `open -n` (which launches even while this one is still running)
/// then terminates the current process.
enum AppRelauncher {
    static func relaunch() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", Bundle.main.bundlePath]
        try? task.run()
        NSApp.terminate(nil)
    }
}
