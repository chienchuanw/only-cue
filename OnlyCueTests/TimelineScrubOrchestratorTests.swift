import XCTest
@testable import OnlyCue

/// Pins the play/pause/resume policy of the waveform-body hold-to-scrub
/// gesture. Geometry (x → time) stays in `CueMarkersGeometry`; state (current
/// scrub time) stays in `ScrubController`. This type owns only the
/// engine-side policy so the gesture handler in `WaveformSeekSurface` can
/// be driven from pure data in tests instead of a live `PlayerEngine`.
final class TimelineScrubOrchestratorTests: XCTestCase {

    func test_begin_whenPlaying_pausesAndStartsScrubAtPressedTime() {
        let effect = TimelineScrubOrchestrator.begin(pressedTime: 7.5, isPlaying: true)
        XCTAssertEqual(effect, .startScrubAndPause(originalTime: 7.5))
    }

    func test_begin_whenPaused_startsScrubAtPressedTime_noPause() {
        let effect = TimelineScrubOrchestrator.begin(pressedTime: 2.0, isPlaying: false)
        XCTAssertEqual(effect, .startScrub(originalTime: 2.0))
    }

    func test_end_seeksToScrubTime_resumeMirrorsResumeOnRelease_true() {
        let state = ScrubController.State(resumeOnRelease: true, originalTime: 5, scrubTime: 9.25)
        let effect = TimelineScrubOrchestrator.end(finished: state)
        XCTAssertEqual(effect, TimelineScrubOrchestrator.EndEffect(seekTo: 9.25, resume: true))
    }

    func test_end_seeksToScrubTime_resumeMirrorsResumeOnRelease_false() {
        let state = ScrubController.State(resumeOnRelease: false, originalTime: 5, scrubTime: 9.25)
        let effect = TimelineScrubOrchestrator.end(finished: state)
        XCTAssertEqual(effect, TimelineScrubOrchestrator.EndEffect(seekTo: 9.25, resume: false))
    }
}
