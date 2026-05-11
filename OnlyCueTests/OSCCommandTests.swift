import XCTest
@testable import OnlyCue

/// Pins the pure mapping from a parsed `OSCMessage` to a typed `OSCCommand`.
/// This is the contract a Companion / MA3 user relies on — every supported
/// address pattern, plus the rejection of unknown ones.
final class OSCCommandTests: XCTestCase {

    private func message(_ address: String, _ args: [OSCArgument] = []) -> OSCMessage {
        OSCMessage(addressPattern: address, arguments: args)
    }

    func test_transportAddresses() {
        XCTAssertEqual(OSCCommand.from(message("/onlycue/play")), .play)
        XCTAssertEqual(OSCCommand.from(message("/onlycue/pause")), .pause)
        XCTAssertEqual(OSCCommand.from(message("/onlycue/stop")), .stop)
    }

    func test_skip_takesIntSeconds() {
        XCTAssertEqual(OSCCommand.from(message("/onlycue/skip", [.int32(5)])), .skip(seconds: 5))
        XCTAssertEqual(OSCCommand.from(message("/onlycue/skip", [.int32(-2)])), .skip(seconds: -2))
    }

    func test_skip_takesFloatSeconds() {
        XCTAssertEqual(OSCCommand.from(message("/onlycue/skip", [.float32(1.5)])), .skip(seconds: 1.5))
    }

    func test_skip_withoutArgument_returnsNil() {
        XCTAssertNil(OSCCommand.from(message("/onlycue/skip")))
    }

    func test_skip_withNonNumericArgument_returnsNil() {
        XCTAssertNil(OSCCommand.from(message("/onlycue/skip", [.string("oops")])))
    }

    func test_locate_takesSeconds() {
        XCTAssertEqual(OSCCommand.from(message("/onlycue/locate", [.float32(30)])), .locate(seconds: 30))
        XCTAssertEqual(OSCCommand.from(message("/onlycue/locate", [.int32(0)])), .locate(seconds: 0))
    }

    func test_cueAddresses() {
        XCTAssertEqual(OSCCommand.from(message("/onlycue/cue/add")), .cueAdd)
        XCTAssertEqual(OSCCommand.from(message("/onlycue/cue/next")), .cueNext)
        XCTAssertEqual(OSCCommand.from(message("/onlycue/cue/prev")), .cuePrev)
    }

    func test_unknownAddress_returnsNil() {
        XCTAssertNil(OSCCommand.from(message("/onlycue/teleport")))
        XCTAssertNil(OSCCommand.from(message("/something/else")))
    }

    func test_supportedAddresses_coverAllCommands() {
        // Every documented address must map to a command. Entries with an
        // argHint need a numeric argument supplied to map successfully.
        for entry in OSCCommand.supportedAddresses {
            let args: [OSCArgument] = entry.argHint == nil ? [] : [.int32(1)]
            XCTAssertNotNil(
                OSCCommand.from(message(entry.address, args)),
                "Documented address \(entry.address) should map to a command"
            )
        }
    }
}
