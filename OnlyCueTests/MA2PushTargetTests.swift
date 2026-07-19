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
}
