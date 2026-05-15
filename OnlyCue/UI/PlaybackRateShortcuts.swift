import AppKit
import SwiftUI

/// Hidden-button shortcut group + LTC-interlocked rate-change handler used by
/// `DocumentView`. Lives in its own file to keep `DocumentView`'s body under
/// the `type_body_length` lint cap.
/// Previous/next cue stepping shortcuts. Extracted from `DocumentView` purely
/// to keep its body under the `type_body_length` lint cap.
struct PlayheadStepShortcuts: View {

    let onStepPrev: () -> Void
    let onStepNext: () -> Void
    let isEnabled: Bool
    let shortcutFor: (KeymapAction) -> KeyboardShortcut

    var body: some View {
        ZStack {
            Button("Previous Cue", action: onStepPrev)
                .keyboardShortcut(shortcutFor(.stepPrevCue))
            Button("Next Cue", action: onStepNext)
                .keyboardShortcut(shortcutFor(.stepNextCue))
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
        .disabled(!isEnabled)
    }
}

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

/// View modifier that wires up the `Playback` menu's notification names and
/// the LTC-enable side effect that auto-resets the rate. Kept in this file so
/// `DocumentView`'s body stays under the `type_body_length` cap.
struct PlaybackRateBindings: ViewModifier {

    let engine: PlayerEngine
    let ltcEnabled: Bool

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .playbackRateUp)) { _ in
                PlaybackRateController.apply(.up, engine: engine, ltcEnabled: ltcEnabled)
            }
            .onReceive(NotificationCenter.default.publisher(for: .playbackRateDown)) { _ in
                PlaybackRateController.apply(.down, engine: engine, ltcEnabled: ltcEnabled)
            }
            .onReceive(NotificationCenter.default.publisher(for: .playbackRateReset)) { _ in
                PlaybackRateController.apply(.reset, engine: engine, ltcEnabled: ltcEnabled)
            }
            .onChange(of: ltcEnabled) { _, newValue in
                // Spec §3.5 (2): turning LTC on while rate != 1.0× resets rate first.
                guard newValue, abs(engine.playbackRate - 1.0) > 0.0001 else { return }
                engine.resetPlaybackRate()
                NotificationCenter.default.post(name: .playbackRateInterlockReset, object: nil)
            }
    }
}

extension View {
    func playbackRateBindings(engine: PlayerEngine, ltcEnabled: Bool) -> some View {
        modifier(PlaybackRateBindings(engine: engine, ltcEnabled: ltcEnabled))
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
