import XCTest
@testable import OnlyCue

/// `MTCLocateGate` holds the decisions `MTCOutputHost` makes on every playhead
/// observation (epic #794): is this a seek, and may a locate go out now?
///
/// Extracted for the same reason `MIDIDispatchGate` was — the host is a SwiftUI
/// modifier and therefore awkward to exercise, while the rules it applies are
/// exactly the part worth pinning.
final class MTCLocateGateTests: XCTestCase {

    // MARK: - Seek detection while playing

    // Normal playback advances the playhead roughly 0.1 s per observation, so
    // ordinary progress must never be mistaken for a seek and re-anchor the
    // stream on every tick.
    func test_isSeekWhilePlaying_ignoresOrdinaryPlaybackAdvance() {
        XCTAssertFalse(MTCLocateGate.isSeekWhilePlaying(from: 10.0, to: 10.1))
        XCTAssertFalse(MTCLocateGate.isSeekWhilePlaying(from: 10.0, to: 10.0))
        XCTAssertFalse(MTCLocateGate.isSeekWhilePlaying(from: 10.0, to: 10.2))
    }

    // Stricter than the LTC path's 1.0 s threshold: a half-second jump is a real
    // seek and a console should be told, not left to slide into position.
    func test_isSeekWhilePlaying_detectsForwardAndBackwardJumps() {
        XCTAssertTrue(MTCLocateGate.isSeekWhilePlaying(from: 10.0, to: 10.5))
        XCTAssertTrue(MTCLocateGate.isSeekWhilePlaying(from: 10.0, to: 9.0))
        XCTAssertTrue(MTCLocateGate.isSeekWhilePlaying(from: 60.0, to: 0.0))
    }

    // MARK: - Locate while paused

    // Paused, there is no stream to protect, so any real move should locate the
    // receiver — the whole point of following a parked playhead.
    func test_isLocateWhilePaused_triggersOnAnyRealMove() {
        XCTAssertTrue(MTCLocateGate.isLocateWhilePaused(from: 10.0, to: 10.05))
        XCTAssertTrue(MTCLocateGate.isLocateWhilePaused(from: 10.0, to: 9.99))
    }

    // Floating-point noise on an unchanged playhead must not emit anything.
    func test_isLocateWhilePaused_ignoresNoise() {
        XCTAssertFalse(MTCLocateGate.isLocateWhilePaused(from: 10.0, to: 10.0))
        XCTAssertFalse(MTCLocateGate.isLocateWhilePaused(from: 10.0, to: 10.0 + 1e-9))
    }

    // MARK: - Throttle

    // Dragging the waveform emits a continuous stream of playhead changes; the
    // port must not be flooded with one Full Frame per pixel.
    func test_shouldSend_throttlesToAboutTenPerSecond() {
        XCTAssertTrue(MTCLocateGate.shouldSend(now: 100.0, lastSentAt: nil))
        XCTAssertFalse(MTCLocateGate.shouldSend(now: 100.05, lastSentAt: 100.0))
        XCTAssertTrue(MTCLocateGate.shouldSend(now: 100.1, lastSentAt: 100.0))
        XCTAssertTrue(MTCLocateGate.shouldSend(now: 101.0, lastSentAt: 100.0))
    }

    // A clock that appears to run backwards (or a stale timestamp) must not latch
    // the throttle closed forever.
    func test_shouldSend_recoversFromANonMonotonicTimestamp() {
        XCTAssertTrue(MTCLocateGate.shouldSend(now: 99.0, lastSentAt: 100.0))
    }
}
