import XCTest
@testable import OnlyCue

/// #683 — `MA2PushTarget` is the per-clip grandMA2 push destination persisted in
/// the document (sequence slot, timecode slot, executor, timecode command, and
/// the cue-type filter used for the last push).
final class MA2PushTargetTests: XCTestCase {

    func test_codableRoundTrip() throws {
        let typeID = UUID()
        let target = MA2PushTarget(
            sequenceSlot: 101,
            timecodeSlot: 7,
            executorPage: 1,
            executorNumber: 101,
            timecodeCommand: .goto,
            includedTypeIDs: [typeID]
        )
        let data = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(MA2PushTarget.self, from: data)
        XCTAssertEqual(decoded, target)
    }

    func test_timecodeCommand_rawValues_areStable() {
        // Persisted in .cuelist documents — renaming a case breaks old files.
        XCTAssertEqual(MA2TimecodeCommand.go.rawValue, "go")
        XCTAssertEqual(MA2TimecodeCommand.goto.rawValue, "goto")
    }

    func test_mediaItem_ma2PushTarget_defaultsToNil_andRoundTrips() throws {
        var item = MediaItem(
            id: UUID(),
            media: MediaReference(displayName: "x.wav", kind: .audio, duration: 60, bookmarkData: Data()),
            cues: []
        )
        XCTAssertNil(item.ma2PushTarget)

        item.ma2PushTarget = MA2PushTarget(
            sequenceSlot: 5,
            timecodeSlot: 5,
            executorPage: 1,
            executorNumber: 15,
            timecodeCommand: .go,
            includedTypeIDs: []
        )
        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(MediaItem.self, from: data)
        XCTAssertEqual(decoded.ma2PushTarget, item.ma2PushTarget)
    }

    // MARK: - Validity (console slots/pages/executors are 1-based; anything
    // below 1 would emit invalid XML indices and telnet commands)

    private func target(
        sequenceSlot: Int = 1,
        timecodeSlot: Int = 1,
        executorPage: Int = 1,
        executorNumber: Int = 1
    ) -> MA2PushTarget {
        MA2PushTarget(
            sequenceSlot: sequenceSlot,
            timecodeSlot: timecodeSlot,
            executorPage: executorPage,
            executorNumber: executorNumber,
            timecodeCommand: .goto,
            includedTypeIDs: []
        )
    }

    func test_allOnes_isValid() {
        XCTAssertTrue(target().isValid)
    }

    func test_zeroOrNegativeComponents_areInvalid() {
        XCTAssertFalse(target(sequenceSlot: 0).isValid)
        XCTAssertFalse(target(timecodeSlot: 0).isValid)
        XCTAssertFalse(target(executorPage: -1).isValid)
        XCTAssertFalse(target(executorNumber: 0).isValid)
    }

    // MARK: - Sequence name (#686)

    func test_sequenceName_defaultsNil_andRoundTrips() throws {
        XCTAssertNil(target().sequenceName)

        var named = target()
        named.sequenceName = "Opening"
        let data = try JSONEncoder().encode(named)
        let decoded = try JSONDecoder().decode(MA2PushTarget.self, from: data)
        XCTAssertEqual(decoded.sequenceName, "Opening")
    }

    func test_decodesLegacyTargetWithoutSequenceName_asNil() throws {
        let json = Data("""
        {"sequenceSlot":1,"timecodeSlot":1,"executorPage":1,"executorNumber":1,"timecodeCommand":"goto","includedTypeIDs":[]}
        """.utf8)
        let decoded = try JSONDecoder().decode(MA2PushTarget.self, from: json)
        XCTAssertNil(decoded.sequenceName)
    }
}
