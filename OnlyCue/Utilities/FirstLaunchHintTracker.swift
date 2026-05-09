import Foundation

/// Session-scoped tracker for one-shot first-launch UI hints. Survives view
/// rebuilds within the same app launch — `WaveformContainer` may be torn
/// down and rebuilt on every media-item switch, which would re-fire any
/// per-instance `@State` flag. This singleton lives at app scope so the
/// hint fires at most once per launch.
@MainActor
final class FirstLaunchHintTracker {

    static let shared = FirstLaunchHintTracker()

    private(set) var hasShownWaveformZoomHint = false

    private init() {}

    func markShown() {
        hasShownWaveformZoomHint = true
    }

    func resetForTesting() {
        hasShownWaveformZoomHint = false
    }
}
