import XCTest
@testable import OnlyCue

/// Pins the OSC 1.0 wire-format parsing OnlyCue relies on: 4-byte-aligned
/// OSC-strings, big-endian int32/float32, the zero-byte type tags, bundle
/// flattening, and graceful nil on malformed input.
final class OSCParserTests: XCTestCase {

    // MARK: - Builders for hand-rolled OSC datagrams

    /// Encodes a string as an OSC-string: UTF-8 bytes, a NUL, then NUL-padded
    /// to the next 4-byte boundary.
    private func oscString(_ string: String) -> Data {
        var bytes = Array(string.utf8)
        bytes.append(0)
        while bytes.count % 4 != 0 { bytes.append(0) }
        return Data(bytes)
    }

    private func bigEndianInt32(_ value: Int32) -> Data {
        withUnsafeBytes(of: value.bigEndian) { Data($0) }
    }

    private func bigEndianFloat32(_ value: Float) -> Data {
        withUnsafeBytes(of: value.bitPattern.bigEndian) { Data($0) }
    }

    // MARK: - Plain messages

    func test_addressOnly_noTypeTags_parsesWithNoArgs() {
        let datagram = oscString("/onlycue/play")
        let message = OSCParser.parse(datagram)
        XCTAssertEqual(message, OSCMessage(addressPattern: "/onlycue/play", arguments: []))
    }

    func test_addressWithEmptyTypeTagString_parsesWithNoArgs() {
        let datagram = oscString("/onlycue/pause") + oscString(",")
        let message = OSCParser.parse(datagram)
        XCTAssertEqual(message, OSCMessage(addressPattern: "/onlycue/pause", arguments: []))
    }

    func test_int32Argument_isBigEndianDecoded() {
        let datagram = oscString("/onlycue/skip") + oscString(",i") + bigEndianInt32(5)
        let message = OSCParser.parse(datagram)
        XCTAssertEqual(message, OSCMessage(addressPattern: "/onlycue/skip", arguments: [.int32(5)]))
    }

    func test_negativeInt32Argument() {
        let datagram = oscString("/onlycue/skip") + oscString(",i") + bigEndianInt32(-3)
        let message = OSCParser.parse(datagram)
        XCTAssertEqual(message, OSCMessage(addressPattern: "/onlycue/skip", arguments: [.int32(-3)]))
    }

    func test_float32Argument_isBigEndianDecoded() throws {
        let datagram = oscString("/onlycue/locate") + oscString(",f") + bigEndianFloat32(12.5)
        let message = try XCTUnwrap(OSCParser.parse(datagram))
        XCTAssertEqual(message.addressPattern, "/onlycue/locate")
        guard case .float32(let value) = try XCTUnwrap(message.arguments.first) else {
            return XCTFail("expected a float32 argument")
        }
        XCTAssertEqual(value, 12.5, accuracy: 0.0001)
    }

    func test_stringArgument_respectsFourBytePadding() {
        // "ab" → 3 bytes ("ab\0") → padded to 4. The parser must skip the pad.
        let datagram = oscString("/cue/jump") + oscString(",s") + oscString("ab")
        let message = OSCParser.parse(datagram)
        XCTAssertEqual(message, OSCMessage(addressPattern: "/cue/jump", arguments: [.string("ab")]))
    }

    func test_multipleArguments_inOrder() {
        let datagram = oscString("/x") + oscString(",if") + bigEndianInt32(2) + bigEndianFloat32(0.5)
        let message = OSCParser.parse(datagram)
        XCTAssertEqual(
            message,
            OSCMessage(addressPattern: "/x", arguments: [.int32(2), .float32(0.5)])
        )
    }

    func test_zeroByteTypeTags() {
        let datagram = oscString("/onlycue/play") + oscString(",TFNI")
        let message = OSCParser.parse(datagram)
        XCTAssertEqual(
            message,
            OSCMessage(addressPattern: "/onlycue/play", arguments: [.true, .false, .null, .impulse])
        )
    }

    // MARK: - Rejection cases

    func test_emptyData_returnsNil() {
        XCTAssertNil(OSCParser.parse(Data()))
    }

    func test_addressNotStartingWithSlash_returnsNil() {
        XCTAssertNil(OSCParser.parse(oscString("onlycue/play")))
    }

    func test_truncatedInt32Argument_returnsNil() {
        // Type tag says ",i" but only 2 bytes of the int follow.
        let datagram = oscString("/onlycue/skip") + oscString(",i") + Data([0x00, 0x05])
        XCTAssertNil(OSCParser.parse(datagram))
    }

    func test_unknownTypeTag_returnsNil() {
        // ",d" (double) — we don't support it; parser bails rather than guess.
        let datagram = oscString("/x") + oscString(",d") + Data(repeating: 0, count: 8)
        XCTAssertNil(OSCParser.parse(datagram))
    }

    // MARK: - Bundles

    func test_bundle_flattensToContainedMessages() {
        let inner1 = oscString("/onlycue/play")
        let inner2 = oscString("/onlycue/pause")
        let datagram = oscString("#bundle")
            + Data(repeating: 0, count: 8) // time tag
            + bigEndianInt32(Int32(inner1.count)) + inner1
            + bigEndianInt32(Int32(inner2.count)) + inner2
        let messages = OSCParser.parseMessages(datagram)
        XCTAssertEqual(messages.map(\.addressPattern), ["/onlycue/play", "/onlycue/pause"])
    }

    func test_bundle_parseTakesFirstMessage() {
        let inner1 = oscString("/onlycue/play")
        let inner2 = oscString("/onlycue/pause")
        let datagram = oscString("#bundle")
            + Data(repeating: 0, count: 8)
            + bigEndianInt32(Int32(inner1.count)) + inner1
            + bigEndianInt32(Int32(inner2.count)) + inner2
        XCTAssertEqual(OSCParser.parse(datagram)?.addressPattern, "/onlycue/play")
    }

    // MARK: - Nesting depth (#835)

    /// Wraps `payload` in `levels` nested `#bundle` containers.
    private func nested(_ payload: Data, levels: Int) -> Data {
        var data = payload
        for _ in 0 ..< levels {
            data = oscString("#bundle")
                + Data(repeating: 0, count: 8)
                + bigEndianInt32(Int32(data.count)) + data
        }
        return data
    }

    func test_bundleNesting_atTheLimit_stillParses() {
        let datagram = nested(oscString("/onlycue/play"), levels: OSCParser.maximumBundleDepth)
        XCTAssertEqual(OSCParser.parseMessages(datagram).map(\.addressPattern), ["/onlycue/play"])
    }

    func test_bundleNesting_oneBeyondTheLimit_yieldsNothing() {
        let datagram = nested(oscString("/onlycue/play"), levels: OSCParser.maximumBundleDepth + 1)
        XCTAssertEqual(OSCParser.parseMessages(datagram), [])
    }

    /// The cap must not abandon the enclosing bundle — that is the same
    /// "skip the bad element, keep the rest" rule a malformed element follows.
    /// Without this, capping would turn one over-deep element into a silent
    /// drop of its well-formed siblings.
    func test_bundleNesting_anOverDeepElement_doesNotDropItsSiblings() {
        let tooDeep = nested(oscString("/onlycue/play"), levels: OSCParser.maximumBundleDepth)
        let sibling = oscString("/onlycue/stop")
        let datagram = oscString("#bundle")
            + Data(repeating: 0, count: 8)
            + bigEndianInt32(Int32(tooDeep.count)) + tooDeep
            + bigEndianInt32(Int32(sibling.count)) + sibling
        XCTAssertEqual(OSCParser.parseMessages(datagram).map(\.addressPattern), ["/onlycue/stop"])
    }

    /// The real reason the cap exists: recursion depth is attacker-controlled,
    /// and a stack overflow is a crash, not a parse failure.
    ///
    /// Deliberately run on a 512 KB thread rather than inline. XCTest runs on
    /// the main thread's 8 MB stack, where 8000 levels simply *parse* — measured
    /// while writing this test, and the reason an earlier version of it was
    /// worthless: it asserted a crash that the test environment cannot produce,
    /// so it would have passed for the wrong reason. 512 KB is the stack size a
    /// dispatch worker actually gets, and ~2800 levels is where that segfaults
    /// (#835), so this exercises the real failure mode.
    func test_bundleNesting_pathologicalDepth_onASmallStack_returnsEmpty() throws {
        let datagram = nested(oscString("/onlycue/play"), levels: 8000)
        var result: [OSCMessage]?

        let thread = Thread { result = OSCParser.parseMessages(datagram) }
        thread.stackSize = 512 * 1024
        thread.start()

        let deadline = Date().addingTimeInterval(10)
        while !thread.isFinished, Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }

        XCTAssertTrue(thread.isFinished, "parser did not finish on a 512 KB stack")
        XCTAssertEqual(try XCTUnwrap(result), [])
    }
}
