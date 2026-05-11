import XCTest
@testable import OnlyCue

/// Pins the two pure pieces the OSC monitor relies on: the status line it shows
/// (listening vs not, with the port) and the one-line rendering of a received
/// `OSCMessage` — address plus space-joined argument descriptions, which is what
/// `OSCServer.recentMessages` stores (newest first) and the monitor tails.
final class OSCMonitorTests: XCTestCase {

    // MARK: - Status line

    func test_statusText_whenListening_namesThePort() {
        XCTAssertEqual(OSCMonitorView.statusText(isListening: true, port: 8000), "Listening on UDP 8000")
        XCTAssertEqual(OSCMonitorView.statusText(isListening: true, port: 9001), "Listening on UDP 9001")
    }

    func test_statusText_whenNotListening_isStopped() {
        XCTAssertEqual(OSCMonitorView.statusText(isListening: false, port: 8000), "Not listening")
    }

    // MARK: - Message line formatting

    func test_formatLine_addressOnly() {
        let message = OSCMessage(addressPattern: "/onlycue/play", arguments: [])
        XCTAssertEqual(OSCServer.formatLine(for: message), "/onlycue/play")
    }

    func test_formatLine_intArgument() {
        let message = OSCMessage(addressPattern: "/onlycue/skip", arguments: [.int32(5)])
        XCTAssertEqual(OSCServer.formatLine(for: message), "/onlycue/skip 5")
    }

    func test_formatLine_floatArgument() {
        let message = OSCMessage(addressPattern: "/onlycue/locate", arguments: [.float32(30.5)])
        XCTAssertEqual(OSCServer.formatLine(for: message), "/onlycue/locate 30.5")
    }

    func test_formatLine_multipleAndStringArguments_areSpaceJoinedAndQuoted() {
        let message = OSCMessage(addressPattern: "/x", arguments: [.string("hi"), .int32(2), .true])
        XCTAssertEqual(OSCServer.formatLine(for: message), "/x \"hi\" 2 T")
    }
}
