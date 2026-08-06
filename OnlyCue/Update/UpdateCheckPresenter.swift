import AppKit

/// Runs a "Check for Updates" check and shows the matching `NSAlert` (#565).
/// App-global and stateless, so `AppCommands`' menu item calls `shared.run()`
/// directly rather than routing through per-document notifications.
@MainActor
final class UpdateCheckPresenter {

    static let shared = UpdateCheckPresenter()

    private let checker: UpdateChecker
    private var isChecking = false

    init(checker: UpdateChecker = UpdateChecker()) {
        self.checker = checker
    }

    func run() async {
        guard !isChecking else { return } // ignore double-clicks while in flight
        isChecking = true
        defer { isChecking = false }
        present(await checker.checkForUpdate())
    }

    private func present(_ result: UpdateCheckResult) {
        let alert = NSAlert()
        switch result {
        case .updateAvailable(let release):
            let latest = release.version.map(String.init(describing:)) ?? release.tagName
            alert.messageText = String(localized: "Update Available")
            var info = String(localized: "OnlyCue \(latest) is available — you have \(AppVersion.currentString).")
            if let body = release.body, !body.isEmpty {
                info += "\n\n" + String(body.prefix(500))
            }
            alert.informativeText = info
            alert.addButton(withTitle: String(localized: "Download"))
            alert.addButton(withTitle: String(localized: "Release Notes…"))
            alert.addButton(withTitle: String(localized: "Later"))
            switch alert.runModal() {
            case .alertFirstButtonReturn: NSWorkspace.shared.open(release.downloadURL)
            case .alertSecondButtonReturn: NSWorkspace.shared.open(release.htmlURL)
            default: break
            }

        case .upToDate(let current):
            alert.messageText = String(localized: "You're up to date")
            alert.informativeText = String(localized: "OnlyCue \(current) is the latest release.")
            alert.addButton(withTitle: String(localized: "OK"))
            alert.runModal()

        case .runningNewerBuild(let current, let latest):
            alert.messageText = String(localized: "You're up to date")
            alert.informativeText =
                String(localized: "You're running a newer build (\(current)) than the latest release (\(latest)).")
            alert.addButton(withTitle: String(localized: "OK"))
            alert.runModal()

        case .failed(let message):
            alert.alertStyle = .warning
            alert.messageText = String(localized: "Couldn't check for updates")
            alert.informativeText = message
            alert.addButton(withTitle: String(localized: "OK"))
            alert.runModal()
        }
    }
}
