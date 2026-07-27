import XCTest
@testable import OnlyCue

final class MIDIMonitorTests: XCTestCase {
    func test_formatLine_rendersControlChange() {
        XCTAssertEqual(MIDIInput.formatLine(for: .controlChange(channel: 1, number: 45, value: 127)),
                       "CC    ch1  #45  127")
    }

    func test_formatLine_rendersNote() {
        XCTAssertEqual(MIDIInput.formatLine(for: .note(channel: 10, number: 60, velocity: 0)),
                       "Note  ch10  #60  0")
    }

    func test_messageCountText_pluralises() {
        XCTAssertEqual(MIDIMonitorView.messageCountText(count: 0), "0 messages")
        XCTAssertEqual(MIDIMonitorView.messageCountText(count: 1), "1 message")
        XCTAssertEqual(MIDIMonitorView.messageCountText(count: 7), "7 messages")
    }

    func test_statusText_namesTheConnectedDevice() {
        XCTAssertEqual(MIDIMonitorView.statusText(isConnected: true, deviceName: "nanoKONTROL2"),
                       "Connected · nanoKONTROL2")
        XCTAssertEqual(MIDIMonitorView.statusText(isConnected: false, deviceName: nil),
                       "No MIDI input selected")
    }
}
