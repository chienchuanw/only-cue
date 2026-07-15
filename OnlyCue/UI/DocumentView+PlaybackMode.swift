import SwiftUI

/// End-of-media dispatch and focus-chain plumbing for the per-document
/// `PlaybackMode`. Kept in its own file so `DocumentView.swift` doesn't grow
/// past the project's file-length lint budget — every member here is logically
/// scoped to the playback-mode feature (added in v15) and would just inflate
/// the main DocumentView body otherwise.
extension DocumentView {

    /// End-of-media dispatcher. The chosen `PlaybackMode` decides whether to
    /// stop, loop the current media, or advance to the next item. Loop and
    /// Auto-Next are *suppressed* while LTC output is active because either
    /// transition would introduce a media-time discontinuity on the LTC
    /// timecode contract — the suppression posts `.ltcInterlockEngaged` (same
    /// signal the speed-key interlock uses) and leaves the document's
    /// `playbackMode` unchanged so the mode resumes the instant LTC is turned
    /// off. The playback rate is preserved across loop wraps and auto-next
    /// transitions (`engine.playbackRate` is sticky between `load()` calls).
    func handleMediaDidReachEnd() {
        switch document.model.playbackMode {
        case .playOnce:
            return
        case .loop:
            if ltcRoutingStore.settings.isEnabled {
                NotificationCenter.default.post(name: .ltcInterlockEngaged, object: nil)
                return
            }
            Task {
                await engine.seek(to: 0)
                engine.play()
            }
        case .autoNext:
            if ltcRoutingStore.settings.isEnabled {
                NotificationCenter.default.post(name: .ltcInterlockEngaged, object: nil)
                return
            }
            Task {
                await CueCommands.advanceToNextMediaAndPlay(
                    document: document,
                    reloadAndPlay: { _ in
                        do {
                            try await MediaImporter.loadActive(into: document, engine: engine, documentDirectory: documentDirectory)
                            engine.play()
                        } catch {
                            if let item = document.model.activeItem {
                                pendingAlert = .relink(itemID: item.id, displayName: item.media.displayName)
                            }
                        }
                    }
                )
            }
        }
    }
}

/// Carries the active document's playback mode up the SwiftUI focus chain so
/// `AppCommands` can render the leading checkmark on the active menu item.
struct CurrentPlaybackModeFocusKey: FocusedValueKey {
    typealias Value = PlaybackMode
}

extension FocusedValues {
    var currentPlaybackMode: PlaybackMode? {
        get { self[CurrentPlaybackModeFocusKey.self] }
        set { self[CurrentPlaybackModeFocusKey.self] = newValue }
    }
}

extension Notification.Name {
    /// Posted by the Playback menu when the user picks a playback mode.
    /// `object` is the `PlaybackMode`. Handled by `DocumentView`.
    static let setPlaybackModeRequested = Notification.Name("OnlyCue.setPlaybackModeRequested")
    /// Posted by the end-of-media dispatcher when LTC is enabled and a Loop /
    /// Auto-Next transition was suppressed. Mirrors the speed-key interlock
    /// signal so existing beep/flash sinks can subscribe uniformly.
    static let ltcInterlockEngaged = Notification.Name("OnlyCue.ltcInterlockEngaged")
}
