import AppKit
import SwiftUI

/// Hidden-button shortcut group + LTC-interlocked rate-change handler used by
/// `DocumentView`. Lives in its own file to keep `DocumentView`'s body under
/// the `type_body_length` lint cap.
struct PlaybackRateShortcuts: View {

    let engine: PlayerEngine
    let ltcEnabled: Bool
    let shortcutFor: (KeymapAction) -> KeyboardShortcut

    var body: some View {
        ZStack {
            Button("Speed Up") { handle(.up) }
                .keyboardShortcut(shortcutFor(.playbackRateUp))
            Button("Slow Down") { handle(.down) }
                .keyboardShortcut(shortcutFor(.playbackRateDown))
            Button("Reset Speed") { handle(.reset) }
                .keyboardShortcut(shortcutFor(.playbackRateReset))
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    enum Change { case up, down, reset }

    func handle(_ change: Change) {
        PlaybackRateController.apply(change, engine: engine, ltcEnabled: ltcEnabled)
    }
}

@MainActor
enum PlaybackRateController {

    static func apply(
        _ change: PlaybackRateShortcuts.Change,
        engine: PlayerEngine,
        ltcEnabled: Bool
    ) {
        let target: Float
        switch change {
        case .up:    target = engine.playbackRate + 0.1
        case .down:  target = engine.playbackRate - 0.1
        case .reset: target = 1.0
        }
        if ltcEnabled && abs(target - 1.0) > 0.0001 {
            NSSound.beep()
            NotificationCenter.default.post(name: .playbackRateInterlockBlocked, object: nil)
            return
        }
        switch change {
        case .up:    engine.nudgePlaybackRate(by: 0.1)
        case .down:  engine.nudgePlaybackRate(by: -0.1)
        case .reset: engine.resetPlaybackRate()
        }
    }
}
