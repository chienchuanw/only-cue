import Foundation

/// Pure decision helper for the waveform timeline's hold-to-scrub gesture.
///
/// The gesture handler in `WaveformSeekSurface` calls `begin` on the first
/// `onChanged` and `end` on `onEnded`. Geometry (x → time) stays in
/// `CueMarkersGeometry`; state (current scrub time) stays in `ScrubController`.
/// This type owns only the play/pause/resume policy so it can be unit-tested
/// without a real `PlayerEngine` or SwiftUI gesture pipeline.
enum TimelineScrubOrchestrator {

    enum BeginEffect: Equatable {
        case startScrubAndPause(originalTime: TimeInterval)
        case startScrub(originalTime: TimeInterval)
    }

    struct EndEffect: Equatable {
        let seekTo: TimeInterval
        let resume: Bool
    }

    static func begin(pressedTime: TimeInterval, isPlaying: Bool) -> BeginEffect {
        isPlaying
            ? .startScrubAndPause(originalTime: pressedTime)
            : .startScrub(originalTime: pressedTime)
    }

    static func end(finished: ScrubController.State) -> EndEffect {
        EndEffect(seekTo: finished.scrubTime, resume: finished.resumeOnRelease)
    }
}
