import XCTest
@testable import OnlyCue

/// #683 — glue between a media item and the push plan: apply the saved
/// cue-type filter (`CueExportFilter` contract: empty = all), run the
/// pre-flight, and assemble the plan with the clip's names / start timecode /
/// length.
final class MA2PushRequestBuilderTests: XCTestCase {

    private let typeA = UUID()
    private let typeB = UUID()

    private func cue(number: Double?, typeID: UUID, time: TimeInterval = 0) -> Cue {
        Cue(
            id: UUID(),
            typeID: typeID,
            cueNumber: number,
            name: "",
            time: time,
            notes: "",
            fadeTime: FadeTime(fadeIn: 0, fadeOut: 0)
        )
    }

    private func item(cues: [Cue], startTimecodeFrames: Int = 0) -> MediaItem {
        MediaItem(
            id: UUID(),
            media: MediaReference(
                displayName: "song.wav",
                kind: .audio,
                duration: 120.5,
                bookmarkData: Data([0x00])
            ),
            cues: cues,
            startTimecodeFrames: startTimecodeFrames,
            ltcMuted: false,
            alternateName: "Opening"
        )
    }

    private func target(includedTypeIDs: Set<UUID> = []) -> MA2PushTarget {
        MA2PushTarget(
            sequenceSlot: 18,
            timecodeSlot: 3,
            executorPage: 2,
            executorNumber: 3,
            timecodeCommand: .goto,
            includedTypeIDs: includedTypeIDs
        )
    }

    private func outcome(item: MediaItem, target: MA2PushTarget) -> MA2PushRequestBuilder.Outcome {
        MA2PushRequestBuilder.outcome(
            item: item,
            target: target,
            framerate: .fps30,
            showfile: "MyShow",
            datetime: "2026-07-19T12:00:00"
        )
    }

    func test_ready_usesResolvedName_andFilteredCues() throws {
        let included = cue(number: 1, typeID: typeA, time: 2)
        let excluded = cue(number: 2, typeID: typeB, time: 5)
        let item = item(cues: [included, excluded])

        let outcome = outcome(item: item, target: target(includedTypeIDs: [typeA]))

        guard case .ready(let plan) = outcome else {
            return XCTFail("expected ready, got \(outcome)")
        }
        // Sequence label = clip's resolved name; timecode label marks the show.
        XCTAssertTrue(plan.commands.contains("Label Sequence 18 \"Opening\""))
        XCTAssertTrue(plan.commands.contains("Label Timecode 3 \"Opening TC\""))
        // Only the included type's cue made it into the XML.
        XCTAssertTrue(plan.sequenceUpload.xml.contains("<Number number=\"1\""))
        XCTAssertFalse(plan.sequenceUpload.xml.contains("<Number number=\"2\""))
    }

    func test_lengthFrames_isStartPlusDurationCeil() {
        // 120.5 s at 30 FPS = 3615 frames; start offset 100 → 3715.
        let item = item(cues: [cue(number: 1, typeID: typeA)], startTimecodeFrames: 100)

        let outcome = outcome(item: item, target: target())

        guard case .ready(let plan) = outcome else {
            return XCTFail("expected ready")
        }
        XCTAssertTrue(plan.timecodeUpload.xml.contains("lenght=\"3715\""))
    }

    func test_preflightIssues_block() {
        let item = item(cues: [cue(number: nil, typeID: typeA)])

        let outcome = outcome(item: item, target: target())

        guard case .blocked(let issues) = outcome else {
            return XCTFail("expected blocked, got \(outcome)")
        }
        XCTAssertEqual(issues.count, 1)
    }

    func test_filterLeavingNoCues_blocksWithNoCues() {
        let item = item(cues: [cue(number: 1, typeID: typeB)])

        let outcome = outcome(item: item, target: target(includedTypeIDs: [typeA]))

        XCTAssertEqual(outcome, .blocked([.noCues]))
    }
}
