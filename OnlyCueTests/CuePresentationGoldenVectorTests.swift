import XCTest
@testable import OnlyCue

/// Vector 8's drift guard, bootstrap and independent correctness pins (#837).
///
/// The generator runs the Swift implementation, so it cannot catch a Swift
/// implementation that is itself wrong — it would happily freeze the mistake
/// into the contract and the C# port would then be "verified" against it.
/// `test_knownValues` is the counterweight: values spelled out by hand from the
/// rules, not harvested from the code.
final class CuePresentationGoldenVectorTests: XCTestCase {

    private func goldenURL() throws -> URL {
        try repoRoot().appendingPathComponent("golden", isDirectory: true)
            .appendingPathComponent("cue-presentation-v1.json")
    }

    /// Hand-spelled pins for the four confirmed cross-platform divergences. If
    /// any of these ever changes on the Swift side, the contract changed and the
    /// C# port must move with it — a silently regenerated vector would hide that.
    func test_knownValues_fadeParseDivergences() {
        // Swift's `.whitespaces` excludes line separators, so the newline
        // survives the trim and `Double` then rejects the string. .NET's `Trim()`
        // would strip it and accept.
        XCTAssertNil(FadeTime.parse("1.5\n"))
        XCTAssertNil(FadeTime.parse("1.5\r"))
        // Tab and NBSP *are* in the set on both sides.
        XCTAssertEqual(FadeTime.parse("1.5\t"), FadeTime.symmetric(1.5))
        XCTAssertEqual(FadeTime.parse("\u{00A0}1.5"), FadeTime.symmetric(1.5))
        // Swift's `Double(String)` accepts the C99 hex-float grammar and .NET's
        // does not, so the grammar was narrowed on the macOS side to close the
        // gap rather than porting a hex-float parser (#841). Both now reject.
        XCTAssertNil(FadeTime.parse("0x1p3"))
        // Rejected only by the explicit `hasPrefix("+")` guard.
        XCTAssertNil(FadeTime.parse("+1"))
        // .NET's TryParse accepts both spellings and Swift's `Double(String)`
        // does not, so only the port has to turn them away — and what does that
        // there is the `0...maximum` range, not the finiteness check (verified
        // by mutation). These pin the shared answer, not either spelling.
        XCTAssertNil(FadeTime.parse("infinity"))
        XCTAssertNil(FadeTime.parse("nan"))
    }

    /// The en dash is the single most likely thing for a hand-port to get wrong,
    /// because it is invisible in a diff and a hyphen renders almost the same.
    func test_knownValues_formatMessageUsesAnEnDash() {
        let message = CueNumberErrorMessage.invalidFormat
        XCTAssertEqual(message, "Use 0.001\u{2013}9999.999, up to 3 decimals.")
        XCTAssertTrue(message.contains("\u{2013}"), "expected U+2013 EN DASH")
        XCTAssertFalse(message.contains("-"), "a hyphen would mean the port typed the ASCII character")
    }

    /// Swift `max(by:)` returns the **first** extremal element. .NET's `MaxBy`
    /// does too (measured), so this is a *negative* result — but an unpinned one
    /// invites a port to reach for `OrderByDescending().First()`, which is not
    /// the same on ties.
    func test_knownValues_activeCuePrefersTheFirstOfATie() throws {
        let cues = try CuePresentationRowFixtures.activeCues.map(CuePresentationGolden.cue)
        let item = MediaItem(
            id: try CuePresentationGolden.uuid(CuePresentationRowFixtures.itemID),
            media: MediaReference(displayName: "song.wav", kind: .audio, duration: 120, bookmarkData: Data()),
            cues: cues
        )
        XCTAssertEqual(item.activeCue(at: 20)?.id, cues[2].id, "the tie at t=20 must resolve to the earlier entry")
        XCTAssertNil(item.activeCue(at: -1))
        XCTAssertEqual(item.activeCue(at: 100)?.id, cues[2].id)
    }

    /// Drift guard + bootstrap, matching vectors 1–7. A missing file is written
    /// and the test fails, so a new contract is committed and reviewed rather
    /// than silently accepted in CI.
    func test_committedVectors_matchCurrentSwiftOutput() throws {
        let url = try goldenURL()
        let generated = try CuePresentationGolden.encoded(CuePresentationGolden.make())
        guard FileManager.default.fileExists(atPath: url.path) else {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try generated.write(to: url)
            return XCTFail("golden/cue-presentation-v1.json was missing — generated it from the Swift "
                + "implementation. Commit the file and re-run. (To regenerate after a "
                + "deliberate change, delete the file first.)")
        }

        let committed = try JSONDecoder().decode(
            CuePresentationGoldenVector.self,
            from: Data(contentsOf: url)
        )
        XCTAssertEqual(
            committed,
            try CuePresentationGolden.make(),
            "golden/cue-presentation-v1.json drifted from the Swift implementation. If the change "
                + "was intentional, delete the file and re-run to regenerate, review the diff, and "
                + "update the C# OnlyCue.Core to match."
        )
    }

    /// Case names are the C# verifier's `[MemberData]` keys, so a duplicate would
    /// make two cases collide into one silently-passing test.
    func test_caseNamesAreUniqueWithinEachGroup() throws {
        let vector = try CuePresentationGolden.make()
        assertUnique(vector.fadeParse.map(\.name), group: "fadeParse")
        assertUnique(vector.fadeFormat.map(\.name), group: "fadeFormat")
        assertUnique(vector.cueNumberValidation.map(\.name), group: "cueNumberValidation")
        assertUnique(vector.cueNumberErrors.map(\.name), group: "cueNumberErrors")
        assertUnique(vector.sectionCount.map(\.name), group: "sectionCount")
        assertUnique(vector.rowTapIntent.map(\.name), group: "rowTapIntent")
        assertUnique(vector.rangeSelection.map(\.name), group: "rangeSelection")
        assertUnique(vector.rowFill.map(\.name), group: "rowFill")
        assertUnique(vector.goFilter.map(\.name), group: "goFilter")
        assertUnique(vector.rowOpacity.map(\.name), group: "rowOpacity")
        assertUnique(vector.activeCue.map(\.name), group: "activeCue")
        assertUnique(vector.emptyState.map(\.name), group: "emptyState")
    }

    /// The boolean groups are meant to be exhaustive, not sampled — a dropped
    /// combination is the kind of gap that reads as coverage.
    func test_booleanGroupsAreExhaustive() throws {
        let vector = try CuePresentationGolden.make()
        XCTAssertEqual(vector.rowFill.count, 8)
        XCTAssertEqual(vector.rowTapIntent.count, CueRowTapModifier.allCases.count * 4)
        XCTAssertEqual(Set(CueRowFill.Resolution.allCases.map(\.rawValue)), Set(vector.rowFill.map(\.expect)))
    }

    private func assertUnique(_ names: [String], group: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(Set(names).count, names.count, "duplicate case name in \(group)", file: file, line: line)
    }
}
