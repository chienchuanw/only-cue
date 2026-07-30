import XCTest
@testable import OnlyCue

final class MIDIInputHostTests: XCTestCase {
    // Press-edge gating: a CC button release must not fire the discrete action.
    func test_shouldDispatchDiscrete_onlyOnPressEdge() {
        let press = MIDIMessage.controlChange(channel: 1, number: 45, value: 127)
        let release = MIDIMessage.controlChange(channel: 1, number: 45, value: 0)
        XCTAssertTrue(MIDIDispatchGate.shouldFireDiscrete(press, previousCCValue: 0))
        XCTAssertFalse(MIDIDispatchGate.shouldFireDiscrete(release, previousCCValue: 127))
    }

    // Continuous has no edge gating — a fader mid-sweep must keep tracking even
    // though its value never crosses a press threshold — so the first move of a
    // sweep always applies.
    func test_continuous_firstMoveAlwaysDispatches() {
        XCTAssertTrue(MIDIDispatchGate.shouldFireContinuous(now: 100, lastFiredAt: nil))
    }

    // Spec confirmed-default 5: rapid fader CC is coalesced to ~frame cadence,
    // so a sweep can't flood the seek path or write UserDefaults per message.
    func test_continuous_coalescesWithinOneFrame() {
        let last: TimeInterval = 100
        XCTAssertFalse(
            MIDIDispatchGate.shouldFireContinuous(now: last + 0.001, lastFiredAt: last),
            "a second CC 1 ms into the frame must be coalesced, not applied"
        )
        XCTAssertTrue(
            MIDIDispatchGate.shouldFireContinuous(now: last + 0.02, lastFiredAt: last),
            "once a frame has elapsed the window reopens"
        )
    }

    // The coalesced value must not be swallowed: the caller re-fires after this
    // delay so the fader's resting position is what finally lands.
    func test_continuousDelay_isRemainderOfTheFrame() {
        XCTAssertEqual(MIDIDispatchGate.continuousDelay(now: 100, lastFiredAt: nil), 0)
        XCTAssertEqual(
            MIDIDispatchGate.continuousDelay(now: 100.006, lastFiredAt: 100),
            MIDIDispatchGate.continuousInterval - 0.006,
            accuracy: 1e-9
        )
        XCTAssertEqual(
            MIDIDispatchGate.continuousDelay(now: 100.5, lastFiredAt: 100),
            0,
            "an already-open window waits for nothing"
        )
    }

    func test_value_extractsVelocityOrCCValue() {
        XCTAssertEqual(MIDIDispatchGate.value(of: .note(channel: 1, number: 60, velocity: 99)), 99)
        XCTAssertEqual(MIDIDispatchGate.value(of: .controlChange(channel: 1, number: 45, value: 12)), 12)
    }
}
