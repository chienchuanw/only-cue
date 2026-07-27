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

    // Continuous always dispatches (no edge gating) — a fader mid-sweep must
    // keep tracking even though its value never crosses a press threshold.
    func test_continuous_alwaysDispatches() {
        let move = MIDIMessage.controlChange(channel: 1, number: 45, value: 64)
        XCTAssertTrue(MIDIDispatchGate.shouldFireContinuous(move))
    }

    func test_value_extractsVelocityOrCCValue() {
        XCTAssertEqual(MIDIDispatchGate.value(of: .note(channel: 1, number: 60, velocity: 99)), 99)
        XCTAssertEqual(MIDIDispatchGate.value(of: .controlChange(channel: 1, number: 45, value: 12)), 12)
    }
}
