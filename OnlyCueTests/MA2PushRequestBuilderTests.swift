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

    // MARK: - Approach A: command outcome (telnet, no XML/FTP)

    private func commandOutcome(item: MediaItem, target: MA2PushTarget) -> MA2PushRequestBuilder.CommandOutcome {
        MA2PushRequestBuilder.commandOutcome(item: item, target: target, framerate: .fps30)
    }

    func test_commandOutcome_ready_returnsCommandList() {
        let item = item(cues: [cue(number: 2, typeID: typeA, time: 5), cue(number: 1, typeID: typeA, time: 2)])

        let outcome = commandOutcome(item: item, target: target())

        guard case .ready(let commands) = outcome else {
            return XCTFail("expected ready, got \(outcome)")
        }
        XCTAssertEqual(commands.first, "Delete Sequence 18 /nc")
        XCTAssertEqual(commands.last, "Assign Sequence 18 At Exec 2.3")
        XCTAssertTrue(commands.contains("Label Sequence 18 \"Opening\""))
        // Number-sorted: cue 1 stored before cue 2.
        guard let store1 = commands.firstIndex(of: "Store Sequence 18 Cue 1 \"\" /nc"),
              let store2 = commands.firstIndex(of: "Store Sequence 18 Cue 2 \"\" /nc") else {
            return XCTFail("both cues should be stored")
        }
        XCTAssertLessThan(store1, store2)
    }

    func test_commandOutcome_blocked_onUnnumberedCue() {
        let item = item(cues: [cue(number: nil, typeID: typeA)])

        let outcome = commandOutcome(item: item, target: target())

        guard case .blocked = outcome else {
            return XCTFail("expected blocked, got \(outcome)")
        }
    }

    // MARK: - Approach C: plugin outcome (downloadable Lua plugin)

    func test_pluginOutcome_ready_wrapsPlanInBundle() {
        let item = item(cues: [cue(number: 1, typeID: typeA, time: 2)])

        let outcome = MA2PushRequestBuilder.pluginOutcome(
            item: item,
            target: target(),
            framerate: .fps30,
            datetime: "2026-07-20T00:00:00"
        )

        guard case .ready(let bundle) = outcome else {
            return XCTFail("expected ready, got \(outcome)")
        }
        XCTAssertTrue(bundle.manifestXML.contains("name=\"Opening\""))
        XCTAssertTrue(bundle.lua.contains("CMD('Label Sequence 18 \"Opening\"')"))
    }

    func test_pluginOutcome_blocked_onUnnumberedCue() {
        let item = item(cues: [cue(number: nil, typeID: typeA)])

        let outcome = MA2PushRequestBuilder.pluginOutcome(
            item: item,
            target: target(),
            framerate: .fps30,
            datetime: "d"
        )

        guard case .blocked = outcome else {
            return XCTFail("expected blocked")
        }
    }

    // MARK: - Resolved sequence name (#686)

    func test_resolvedName_prefersTargetSequenceName() {
        var t = target()
        t.sequenceName = "My Cues"
        let item = item(cues: [cue(number: 1, typeID: typeA, time: 0)])

        guard case .ready(let commands) = MA2PushRequestBuilder.commandOutcome(item: item, target: t, framerate: .fps30) else {
            return XCTFail("expected ready")
        }
        XCTAssertTrue(commands.contains("Label Sequence 18 \"My Cues\""))
    }

    func test_resolvedName_sanitizesResolvedName_whenTargetNameNil() {
        let item = item(cues: [cue(number: 1, typeID: typeA, time: 0)])

        guard case .ready(let commands) = MA2PushRequestBuilder.commandOutcome(item: item, target: target(), framerate: .fps30) else {
            return XCTFail("expected ready")
        }
        XCTAssertTrue(commands.contains("Label Sequence 18 \"Opening\""))
    }
}
