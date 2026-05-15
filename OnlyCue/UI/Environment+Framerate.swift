import SwiftUI

private struct ProjectFramerateKey: EnvironmentKey {
    /// Default keeps previews and isolated tests sensible without manual injection.
    static let defaultValue: SMPTEFramerate = .fps30
}

extension EnvironmentValues {
    /// The project's currently-configured SMPTE framerate, seeded once at the
    /// `DocumentView` body root from `project.timecodeSettings.framerate`. UI
    /// time formatters consume this via `@Environment(\.projectFramerate)`.
    var projectFramerate: SMPTEFramerate {
        get { self[ProjectFramerateKey.self] }
        set { self[ProjectFramerateKey.self] = newValue }
    }
}
