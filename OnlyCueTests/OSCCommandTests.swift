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

    // MARK: - Non-finite numeric arguments yield no command (#845)

    func test_skip_withNaN_returnsNil() {
        XCTAssertNil(OSCCommand.from(message("/onlycue/skip", [.float32(.nan)])))
    }

    func test_skip_withSignallingNaN_returnsNil() {
        XCTAssertNil(OSCCommand.from(message("/onlycue/skip", [.float32(Float(bitPattern: 0x7F80_0001))])))
    }

    func test_skip_withInfinity_returnsNil() {
        XCTAssertNil(OSCCommand.from(message("/onlycue/skip", [.float32(.infinity)])))
        XCTAssertNil(OSCCommand.from(message("/onlycue/skip", [.float32(-.infinity)])))
    }

    func test_locate_withNonFiniteArgument_returnsNil() {
        XCTAssertNil(OSCCommand.from(message("/onlycue/locate", [.float32(.nan)])))
        XCTAssertNil(OSCCommand.from(message("/onlycue/locate", [.float32(.infinity)])))
    }

    /// The guard against over-rejecting: `greatestFiniteMagnitude` is absurd as a
    /// seek but it is *finite*, so it still maps. Only NaN and ±∞ are refused.
    func test_skip_withHugeButFiniteArgument_stillMaps() {
        let huge = Float.greatestFiniteMagnitude
        XCTAssertEqual(
            OSCCommand.from(message("/onlycue/skip", [.float32(huge)])),
            .skip(seconds: Double(huge))
        )
    }

    func test_locate_takesSeconds() {
        XCTAssertEqual(OSCCommand.from(message("/onlycue/locate", [.float32(30)])), .locate(seconds: 30))
        XCTAssertEqual(OSCCommand.from(message("/onlycue/locate", [.int32(0)])), .locate(seconds: 0))
    }

    func test_cueAddresses() {
        XCTAssertEqual(OSCCommand.from(message("/onlycue/cue/add")), .cueAdd)
        XCTAssertEqual(OSCCommand.from(message("/onlycue/cue/next")), .cueNext)
        XCTAssertEqual(OSCCommand.from(message("/onlycue/cue/prev")), .cuePrev)
        XCTAssertEqual(OSCCommand.from(message("/onlycue/cue/go")), .cueGo)
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
