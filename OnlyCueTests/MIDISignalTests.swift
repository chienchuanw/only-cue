import XCTest
@testable import OnlyCue

final class MIDISignalTests: XCTestCase {
    // Discrete press edge
    func test_noteOn_isPress() {
        XCTAssertTrue(MIDISignal.isPressEdge(.note(channel: 1, number: 60, velocity: 1),
                                             previousCCValue: nil))
    }
    func test_noteOff_isNotPress() {
        XCTAssertFalse(MIDISignal.isPressEdge(.note(channel: 1, number: 60, velocity: 0),
                                              previousCCValue: nil))
    }
    func test_cc_risingThrough64_isPress() {
        XCTAssertTrue(MIDISignal.isPressEdge(.controlChange(channel: 1, number: 45, value: 127),
                                             previousCCValue: 0))
    }
    func test_cc_stayingHigh_isNotPress() {
        XCTAssertFalse(MIDISignal.isPressEdge(.controlChange(channel: 1, number: 45, value: 100),
                                              previousCCValue: 127))
    }
    func test_cc_firstMessageAtHigh_isPress() {
        // No previous value → treat prior as 0, so a first ≥64 counts as a press.
        XCTAssertTrue(MIDISignal.isPressEdge(.controlChange(channel: 1, number: 45, value: 127),
                                             previousCCValue: nil))
    }

    // Continuous scaling
    func test_normalized_endpoints() {
        XCTAssertEqual(MIDISignal.normalized(0), 0, accuracy: 0.0001)
        XCTAssertEqual(MIDISignal.normalized(127), 1, accuracy: 0.0001)
    }
    func test_scrubTime_mapsAcrossDuration() {
        XCTAssertEqual(MIDISignal.scrubTime(value: 127, duration: 200), 200, accuracy: 0.0001)
        XCTAssertEqual(MIDISignal.scrubTime(value: 0, duration: 200), 0, accuracy: 0.0001)
    }
    func test_playbackRate_mapsToRangeEndpoints() {
        let range: ClosedRange<Float> = 0.1...3.0
        XCTAssertEqual(MIDISignal.playbackRate(value: 0, range: range), 0.1, accuracy: 0.0001)
        XCTAssertEqual(MIDISignal.playbackRate(value: 127, range: range), 3.0, accuracy: 0.0001)
    }
    func test_ltcLevel_endpoints() {
        XCTAssertEqual(MIDISignal.ltcLevel(value: 0), 0, accuracy: 0.0001)
        XCTAssertEqual(MIDISignal.ltcLevel(value: 127), 1, accuracy: 0.0001)
    }
}
