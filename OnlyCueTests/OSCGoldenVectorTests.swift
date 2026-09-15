import XCTest
@testable import OnlyCue

// The cross-platform golden-vector contract for the OSC receive path (epic #728,
// M1c — vector 6 of the seven in
// `docs/superpowers/specs/2026-09-14-windows-m1-contract-design.md`).
//
// macOS is the source of truth: this file emits `golden/osc-v1.json` from
// `OSCParser` + `OSCCommand.from`, and the C# `OnlyCue.Core` re-implementation
// must reproduce every case (verified on Windows CI).
//
// This is the only part of the M1 core that reads untrusted bytes off the
// network, and byte-level parsers are exactly where a hand-port diverges
// silently. Three defaults differ between the platforms and would each produce a
// parser that still "works": .NET reads integers in host (little-endian) order
// where OSC is big-endian; `Encoding.UTF8.GetString` substitutes U+FFFD where
// Swift's `String(data:encoding:.utf8)` returns nil; and a `==` comparison of
// float arguments would hide `-0.0`. The fixtures in `OSCGoldenFixtures.swift`
// pin all three, along with the padding arithmetic and every malformed branch.
//
// NaN float arguments are now among them, which they could not be until #833:
// the transport spelled them "nan", and .NET reads that back as its own
// `double.NaN` (0xFFF8…) where a widened binary32 NaN is 0x7FF8…, so the bitwise
// comparison would have reported drift that isn't there. `GoldenDouble` carries
// the bit pattern instead, which is what lets the two NaN cases exist at all.

// MARK: - Contract model (mirrored by the C# verifier's DTO)

struct OSCGoldenVector: Codable, Equatable {
    let contract: String   // "osc"
    let version: Int       // 1
    let note: String
    let cases: [Case]

    struct Case: Codable, Equatable {
        let name: String
        /// The datagram, base64-encoded. Both sides decode it and feed the raw
        /// bytes to their parser.
        let datagram: String
        /// Everything `parseMessages` returns — empty for a malformed datagram.
        let messages: [Message]
        /// `OSCCommand.from(parse(datagram))`, i.e. the mapping applied to the
        /// *first* message only. Absent when no command results.
        let command: Command?
    }

    struct Message: Codable, Equatable {
        let address: String
        let arguments: [Argument]
    }

    /// A tagged union flattened for JSON: `type` selects which payload field, if
    /// any, is present. The four zero-byte types carry none.
    struct Argument: Codable, Equatable {
        let type: String
        let int: Int32?
        let float: GoldenDouble?
        let text: String?
    }

    struct Command: Codable, Equatable {
        let kind: String
        let seconds: GoldenDouble?
    }
}

// MARK: - Generator (the Swift implementation IS the contract source of truth)

enum OSCGolden {

    private static func argument(_ value: OSCArgument) -> OSCGoldenVector.Argument {
        switch value {
        case .int32(let number):
            .init(type: "int32", int: number, float: nil, text: nil)
        case .float32(let number):
            // Widening binary32 to binary64 is exact and injective, so the
            // double spelled here is the float, losslessly.
            .init(type: "float32", int: nil, float: GoldenDouble(Double(number)), text: nil)
        case .string(let text):
            .init(type: "string", int: nil, float: nil, text: text)
        case .true:
            .init(type: "true", int: nil, float: nil, text: nil)
        case .false:
            .init(type: "false", int: nil, float: nil, text: nil)
        case .null:
            .init(type: "null", int: nil, float: nil, text: nil)
        case .impulse:
            .init(type: "impulse", int: nil, float: nil, text: nil)
        }
    }

    private static func command(_ value: OSCCommand) -> OSCGoldenVector.Command {
        switch value {
        case .play: .init(kind: "play", seconds: nil)
        case .pause: .init(kind: "pause", seconds: nil)
        case .stop: .init(kind: "stop", seconds: nil)
        case .skip(let seconds): .init(kind: "skip", seconds: GoldenDouble(seconds))
        case .locate(let seconds): .init(kind: "locate", seconds: GoldenDouble(seconds))
        case .cueAdd: .init(kind: "cueAdd", seconds: nil)
        case .cueNext: .init(kind: "cueNext", seconds: nil)
        case .cuePrev: .init(kind: "cuePrev", seconds: nil)
        case .cueGo: .init(kind: "cueGo", seconds: nil)
        }
    }

    private static func vectorCase(_ fixture: OSCGoldenCase) -> OSCGoldenVector.Case {
        let messages = OSCParser.parseMessages(fixture.datagram)
        return OSCGoldenVector.Case(
            name: fixture.name,
            datagram: fixture.datagram.base64EncodedString(),
            messages: messages.map { message in
                .init(address: message.addressPattern, arguments: message.arguments.map(argument))
            },
            command: OSCParser.parse(fixture.datagram).flatMap(OSCCommand.from).map(command)
        )
    }

    static func make() -> OSCGoldenVector {
        OSCGoldenVector(
            contract: "osc",
            version: 1,
            note: "macOS-generated golden vectors for OnlyCue's OSC receive path "
                + "(OSCParser.parseMessages / .parse and OSCCommand.from). Each case is a "
                + "base64 datagram, the full message list it parses to, and the command the "
                + "first message maps to. An empty message list is the contract for malformed "
                + "input: the parser must return nothing and must not throw. Floats are "
                + "carried as their exactly-widened double, in round-trip-exact decimal; "
                + "compare the parsed IEEE-754 bit patterns, not the text. To regenerate "
                + "after a deliberate change, delete golden/osc-v1.json and re-run the test "
                + "suite.",
            cases: OSCGoldenCases.all.map(vectorCase)
        )
    }

    /// Deterministic encoding so the committed file is stable and diff-friendly.
    static func encoded(_ vector: OSCGoldenVector) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(vector)
    }
}

// MARK: - Tests

final class OSCGoldenVectorTests: XCTestCase {

    /// `/onlycue/skip`, NUL-terminated and padded to 16 bytes.
    private static let skipAddress: [UInt8] = [
        0x2F, 0x6F, 0x6E, 0x6C, 0x79, 0x63, 0x75, 0x65,
        0x2F, 0x73, 0x6B, 0x69, 0x70, 0x00, 0x00, 0x00
    ]

    private func goldenURL() throws -> URL {
        try repoRoot().appendingPathComponent("golden", isDirectory: true)
            .appendingPathComponent("osc-v1.json")
    }

    private func skipDatagram(_ tail: [UInt8]) -> Data {
        Data(Self.skipAddress + tail)
    }

    /// Independent correctness pins, spelled out byte by byte from the OSC 1.0
    /// wire format, so a wrong Swift implementation fails here rather than
    /// silently baking a wrong "golden" value.
    func test_knownValues() {
        // ",i" + 5. The type-tag string is 3 bytes incl. the NUL, padded to 4.
        let five = skipDatagram([0x2C, 0x69, 0x00, 0x00, 0x00, 0x00, 0x00, 0x05])
        XCTAssertEqual(
            OSCParser.parse(five),
            OSCMessage(addressPattern: "/onlycue/skip", arguments: [.int32(5)])
        )
        XCTAssertEqual(OSCCommand.from(OSCMessage(addressPattern: "/onlycue/skip", arguments: [.int32(5)])),
                       .skip(seconds: 5))

        // Big-endian 0x00000100. A host-order read on Windows would see 65536.
        let twoFiftySix = skipDatagram([0x2C, 0x69, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00])
        XCTAssertEqual(OSCParser.parse(twoFiftySix)?.arguments, [.int32(256)])

        // Big-endian binary32 1.0 is 0x3F800000.
        let one = skipDatagram([0x2C, 0x66, 0x00, 0x00, 0x3F, 0x80, 0x00, 0x00])
        XCTAssertEqual(OSCParser.parse(one)?.arguments, [.float32(1)])

        // ",si" + "abcd" + 42. "abcd" is 4 bytes, so the NUL pushes it to 8 —
        // the int only reads 42 if the padding consumed exactly three extra
        // bytes.
        let padded = skipDatagram([0x2C, 0x73, 0x69, 0x00,
                                   0x61, 0x62, 0x63, 0x64, 0x00, 0x00, 0x00, 0x00,
                                   0x00, 0x00, 0x00, 0x2A])
        XCTAssertEqual(OSCParser.parse(padded)?.arguments, [.string("abcd"), .int32(42)])

        // 0xFF 0xFE is not valid UTF-8; the message is dropped entirely.
        XCTAssertNil(OSCParser.parse(skipDatagram([0x2C, 0x73, 0x00, 0x00, 0xFF, 0xFE, 0x00, 0x00])))

        // The second argument is short, so the first is discarded too.
        XCTAssertNil(OSCParser.parse(skipDatagram([0x2C, 0x69, 0x66, 0x00, 0x00, 0x00, 0x00, 0x03, 0x00, 0x00])))

        XCTAssertNil(OSCParser.parse(Data()))
        XCTAssertEqual(OSCParser.parseMessages(Data()), [])
    }

    /// Drift guard + bootstrap, matching the other M1 generators. A missing file
    /// is written and the test fails, so a new contract is committed and
    /// reviewed rather than silently accepted in CI.
    func test_committedVectors_matchCurrentSwiftOutput() throws {
        let url = try goldenURL()
        let generated = try OSCGolden.encoded(OSCGolden.make())
        guard FileManager.default.fileExists(atPath: url.path) else {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try generated.write(to: url)
            return XCTFail("golden/osc-v1.json was missing — generated it from the Swift "
                + "implementation. Commit the file and re-run. (To regenerate after a "
                + "deliberate change, delete the file first.)")
        }

        let committed = try JSONDecoder().decode(OSCGoldenVector.self, from: Data(contentsOf: url))
        XCTAssertEqual(
            committed,
            OSCGolden.make(),
            "golden/osc-v1.json drifted from the Swift implementation. If the change was "
                + "intentional, delete the file and re-run to regenerate, review the diff, "
                + "and update the C# OnlyCue.Core to match."
        )
    }

    /// Case names are the C# verifier's `[MemberData]` keys, so a duplicate
    /// would make two cases collide into one silently-passing test.
    func test_caseNamesAreUnique() {
        let names = OSCGoldenCases.all.map(\.name)
        XCTAssertEqual(Set(names).count, names.count)
    }
}
