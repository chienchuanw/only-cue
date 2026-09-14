import XCTest
@testable import OnlyCue

// Tests for the grandMA2 **telnet** golden-vector contract (epic #728, M1c).
// The fixtures and the generator that emits `golden/ma2-telnet-v1.json` live in
// `MA2TelnetGoldenFixtures.swift`; this file only asserts against them, matching
// the split used by the OSC vector.

final class MA2TelnetGoldenVectorTests: XCTestCase {

    private func goldenURL() throws -> URL {
        try repoRoot().appendingPathComponent("golden", isDirectory: true)
            .appendingPathComponent("ma2-telnet-v1.json")
    }

    /// Independent correctness pins, hand-computed from the documented rules, so a
    /// wrong Swift implementation fails here rather than baking a wrong "golden".
    func test_knownValues() {
        // 0.5 s × 25 fps == 12.5 exactly. Away-from-zero → 13 frames → 13/25 s.
        XCTAssertEqual(MA2TrigTime.seconds(cueTime: 0.5, startTimecodeFrames: 0, framerate: .fps25), 0.52)
        XCTAssertEqual(MA2TrigTime.command(cueTime: 0.5, startTimecodeFrames: 0, framerate: .fps25), "0.52")
        // 0.75 s × 30 fps == 22.5 exactly → 23 frames → 23/30 s, six places.
        XCTAssertEqual(MA2TrigTime.command(cueTime: 0.75, startTimecodeFrames: 0, framerate: .fps30), "0.766667")
        // A whole number of frames trims the decimal point entirely.
        XCTAssertEqual(MA2TrigTime.command(cueTime: 5, startTimecodeFrames: 0, framerate: .fps25), "5")
        // 0.29 s × 25 fps == 7.2499…, the only fraction here inside (0, 0.5): it
        // rounds *down* to 7 frames → 7/25 s. `.rounded(.up)` would give 8 → 0.32,
        // and it is the sole case that rules round-up out.
        XCTAssertEqual(MA2TrigTime.command(cueTime: 0.29, startTimecodeFrames: 0, framerate: .fps25), "0.28")

        // 0.0125 × 1000 == 12.5 exactly → 13 thousandths; banker's would give 12.
        XCTAssertEqual(MA2CueNumber.components(from: 0.0125), .init(number: 0, subNumber: 13))
        XCTAssertEqual(MA2CueNumber.commandString(from: 0.0125), "0.013")
        XCTAssertEqual(MA2CueNumber.commandString(from: 3), "3")
        XCTAssertEqual(MA2CueNumber.commandString(from: 4.12), "4.12")
        // 1.0001 × 1000 == 1000.1 → rounds down to 1000; round-up would give
        // 1001, i.e. cue "1.001" instead of cue "1".
        XCTAssertEqual(MA2CueNumber.components(from: 1.0001), .init(number: 1, subNumber: 0))
        XCTAssertEqual(MA2CueNumber.commandString(from: 1.0001), "1")

        // #830: outside grandMA2's 0.001...9999.999 numbering domain the split
        // collapses to an unnumbered cue. This used to be where the two cores
        // were most fragile — `%03d` pads to three columns *including* the sign
        // while .NET's "D3" pads the digits and prepends it, so -1.05 spelled
        // "-1.-5" on one side and "-1.-05" on the other — and it is unreachable
        // on both now, because no negative sub number is ever produced.
        XCTAssertEqual(MA2CueNumber.components(from: -1.5), .init(number: 0, subNumber: 0))
        XCTAssertEqual(MA2CueNumber.commandString(from: -1.5), "0")
        XCTAssertEqual(MA2CueNumber.commandString(from: 0.0005), "0")
        XCTAssertEqual(MA2CueNumber.commandString(from: 10_000), "0")
        // The guard also retires the Int32 hazard: 3e6 × 1000 is 3e9, past
        // Int32.max (2147483647), where a 32-bit port would have saturated.
        // In domain the scaled value tops out at 9_999_999, so 32-bit and
        // 64-bit agree everywhere the function still computes.
        XCTAssertEqual(MA2CueNumber.commandString(from: 3_000_000), "0")
        XCTAssertEqual(MA2CueNumber.components(from: 9999.999), .init(number: 9999, subNumber: 999))
        XCTAssertEqual(MA2CueNumber.commandString(from: 9999.999), "9999.999")

        XCTAssertEqual(MA2Name.sanitize("Song \t  One  ", fallbackSlot: 7), "Song One")
        XCTAssertEqual(MA2Name.sanitize("Set 🎵 One", fallbackSlot: 7), "Set One")
        XCTAssertEqual(MA2Name.sanitize("第一首歌", fallbackSlot: 12), "OnlyCue 12")

        // The fade spelling reaches the wire verbatim, so pin it directly.
        XCTAssertEqual(FadeTime.formatNumber(2.5), "2.5")
        XCTAssertEqual(FadeTime.formatNumber(3), "3")
        XCTAssertEqual(FadeTime.formatNumber(0.1 + 0.2), "0.30000000000000004")
        // Under 1e-4 Swift goes exponential, lowercase marker, two exponent
        // digits. .NET's "R" agrees on everything but the case of the `e`.
        XCTAssertEqual(FadeTime.formatNumber(0.00001), "1e-05")
        // At the other end, a whole number stays fully spelled out: .NET's "R"
        // turns exponential here, so this is what keeps the two sides aligned.
        XCTAssertEqual(FadeTime.formatNumber(1e17), "100000000000000000")
    }

    /// Drift guard + bootstrap, matching the M1a/M1b generators. A missing file is
    /// written and the test fails, so a new contract is committed and reviewed
    /// rather than silently accepted in CI.
    func test_committedVectors_matchCurrentSwiftOutput() throws {
        let url = try goldenURL()
        let generated = try MA2TelnetGolden.encoded(MA2TelnetGolden.make())
        guard FileManager.default.fileExists(atPath: url.path) else {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try generated.write(to: url)
            return XCTFail("golden/ma2-telnet-v1.json was missing — generated it from the "
                + "Swift implementation. Commit the file and re-run. (To regenerate after a "
                + "deliberate change, delete the file first.)")
        }

        let committed = try JSONDecoder().decode(
            MA2TelnetGoldenVector.self, from: Data(contentsOf: url)
        )
        XCTAssertEqual(
            committed,
            MA2TelnetGolden.make(),
            "golden/ma2-telnet-v1.json drifted from the Swift implementation. If the change "
                + "was intentional, delete the file and re-run to regenerate, review the diff, "
                + "and update the C# OnlyCue.Core to match."
        )
    }
}
