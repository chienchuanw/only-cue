import XCTest
@testable import OnlyCue

final class TempoMapTests: XCTestCase {

    // MARK: - Normalization invariants

    func test_emptyMap_hasNoSections() {
        XCTAssertTrue(TempoMap().isEmpty)
        XCTAssertNil(TempoMap().section(atSeconds: 10))
        XCTAssertNil(TempoMap().nearestBeat(toSeconds: 10, itemDuration: 100))
        XCTAssertEqual(TempoMap().beatTimes(in: 0...100, itemDuration: 100).count, 0)
    }

    func test_init_sortsSectionsAndForcesFirstToZero() {
        let map = TempoMap(sections: [
            TempoSection(startSeconds: 30, bpm: 140),
            TempoSection(startSeconds: 10, bpm: 120)
        ])
        XCTAssertEqual(map.sections.map(\.startSeconds), [0, 30])
        XCTAssertEqual(map.sections.first?.bpm, 120, "the earliest section becomes the first and is pinned to 0")
    }

    func test_init_dedupesEqualStarts_keepingLast() {
        let map = TempoMap(sections: [
            TempoSection(startSeconds: 20, bpm: 100),
            TempoSection(startSeconds: 20, bpm: 160)
        ])
        XCTAssertEqual(map.sections.count, 1)
        XCTAssertEqual(map.sections.first?.bpm, 160)
    }

    func test_section_clampsBPMAndBeatsPerBar() {
        let lo = TempoSection(startSeconds: 0, bpm: 1, beatsPerBar: 0)
        XCTAssertEqual(lo.bpm, TempoSection.minBPM)
        XCTAssertEqual(lo.beatsPerBar, 1)
        let hi = TempoSection(startSeconds: 0, bpm: 9_000)
        XCTAssertEqual(hi.bpm, TempoSection.maxBPM)
    }

    func test_init_reducesDownbeatOffsetIntoOneBar() {
        // 120 BPM, 4/4 -> beatDuration 0.5, barDuration 2.0; offset 5.0 -> 1.0
        let map = TempoMap(sections: [
            TempoSection(startSeconds: 0, bpm: 120, beatsPerBar: 4, downbeatOffsetSeconds: 5.0)
        ])
        XCTAssertEqual(try XCTUnwrap(map.sections.first).downbeatOffsetSeconds, 1.0, accuracy: 1e-9)
    }

    // MARK: - section(atSeconds:)

    func test_sectionAtSeconds_picksTheCoveringSection() {
        let map = TempoMap(sections: [
            TempoSection(startSeconds: 0, bpm: 120),
            TempoSection(startSeconds: 30, bpm: 140),
            TempoSection(startSeconds: 60, bpm: 90)
        ])
        XCTAssertEqual(map.section(atSeconds: -5)?.bpm, 120)
        XCTAssertEqual(map.section(atSeconds: 0)?.bpm, 120)
        XCTAssertEqual(map.section(atSeconds: 29.9)?.bpm, 120)
        XCTAssertEqual(map.section(atSeconds: 30)?.bpm, 140)
        XCTAssertEqual(map.section(atSeconds: 1000)?.bpm, 90)
    }

    func test_sectionEndSeconds_isNextStartOrItemDuration() {
        let map = TempoMap(sections: [
            TempoSection(startSeconds: 0, bpm: 120),
            TempoSection(startSeconds: 30, bpm: 140)
        ])
        XCTAssertEqual(map.sectionEndSeconds(for: map.sections[0], itemDuration: 100), 30)
        XCTAssertEqual(map.sectionEndSeconds(for: map.sections[1], itemDuration: 100), 100)
    }

    // MARK: - beatTimes / barTimes

    func test_beatTimes_44_spacingAndDownbeatTagging() {
        // 120 BPM, 4/4: beats every 0.5 s; downbeat every 4th (0, 2, 4, ...)
        let map = TempoMap.singleSection(bpm: 120, beatsPerBar: 4)
        let beats = map.beatTimes(in: 0...4, itemDuration: 8)
        XCTAssertEqual(beats.map(\.time), [0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0])
        XCTAssertEqual(beats.filter(\.isDownbeat).map(\.time), [0, 2.0, 4.0])
    }

    func test_beatTimes_34_downbeatsEveryThreeBeats() {
        // 180 BPM, 3/4: beats every 1/3 s; downbeats at 0, 1.0, 2.0, ...
        let map = TempoMap.singleSection(bpm: 180, beatsPerBar: 3)
        let downbeats = map.barTimes(in: 0...2, itemDuration: 10)
        XCTAssertEqual(downbeats.count, 3)
        XCTAssertEqual(downbeats[1], 1.0, accuracy: 1e-9)
        XCTAssertEqual(downbeats[2], 2.0, accuracy: 1e-9)
    }

    func test_beatTimes_withDownbeatOffsetGreaterThanOneBeat_hasPartialLeadingBar() {
        // 120 BPM, 4/4 (beat 0.5 s, bar 2.0 s). First downbeat at 1.3 s.
        // So beats also exist at 0.8, 0.3 (before the first downbeat) within the span.
        let map = TempoMap.singleSection(bpm: 120, beatsPerBar: 4, downbeatOffsetSeconds: 1.3)
        let beats = map.beatTimes(in: 0...3, itemDuration: 6)
        let round6: (TimeInterval) -> TimeInterval = { ($0 * 1e6).rounded() / 1e6 }
        XCTAssertEqual(beats.map { round6($0.time) }, [0.3, 0.8, 1.3, 1.8, 2.3, 2.8].map(round6))
        // The first downbeat in range is 1.3 (beat index 0); the next is 3.3 (out of range).
        XCTAssertEqual(beats.filter(\.isDownbeat).map { round6($0.time) }, [1.3].map(round6))
    }

    func test_beatTimes_multiSection_eachAtItsOwnTempo_boundaryBelongsToNextSection() {
        let map = TempoMap(sections: [
            TempoSection(startSeconds: 0, bpm: 120, beatsPerBar: 4),   // beats 0, 0.5, 1.0, ...
            TempoSection(startSeconds: 2, bpm: 240, beatsPerBar: 4)    // beats 2.0, 2.25, 2.5, ...
        ])
        let beats = map.beatTimes(in: 0...3, itemDuration: 4).map(\.time)
        // Section 1 covers [0, 2): 0, 0.5, 1.0, 1.5 (2.0 belongs to section 2).
        // Section 2 covers [2, 4]: 2.0, 2.25, 2.5, 2.75, 3.0.
        XCTAssertEqual(beats.prefix(4).map { ($0 * 1e6).rounded() / 1e6 }, [0, 0.5, 1.0, 1.5])
        XCTAssertEqual(beats.filter { abs($0 - 2.0) < 1e-9 }.count, 1, "2.0 must appear exactly once")
        XCTAssertTrue(beats.contains { abs($0 - 2.25) < 1e-9 })
    }

    func test_beatTimes_windowedToVisibleRange() {
        let map = TempoMap.singleSection(bpm: 120, beatsPerBar: 4)   // beat every 0.5 s
        let beats = map.beatTimes(in: 10...11, itemDuration: 100).map(\.time)
        XCTAssertEqual(beats, [10.0, 10.5, 11.0])
    }

    // MARK: - nearestBeat / nearestBar

    func test_nearestBeat_roundsToTheGrid() {
        let map = TempoMap.singleSection(bpm: 120, beatsPerBar: 4)   // beats every 0.5 s
        XCTAssertEqual(try XCTUnwrap(map.nearestBeat(toSeconds: 1.24, itemDuration: 100)), 1.0, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(map.nearestBeat(toSeconds: 1.26, itemDuration: 100)), 1.5, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(map.nearestBeat(toSeconds: 2.0, itemDuration: 100)), 2.0, accuracy: 1e-9)
    }

    func test_nearestBar_roundsToDownbeats() {
        let map = TempoMap.singleSection(bpm: 120, beatsPerBar: 4)   // bar every 2.0 s
        XCTAssertEqual(try XCTUnwrap(map.nearestBar(toSeconds: 0.9, itemDuration: 100)), 0.0, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(map.nearestBar(toSeconds: 1.1, itemDuration: 100)), 2.0, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(map.nearestBar(toSeconds: 7.4, itemDuration: 100)), 8.0, accuracy: 1e-9)
    }

    func test_nearestBeat_staysInsideItsSectionSpan() throws {
        let map = TempoMap(sections: [
            TempoSection(startSeconds: 0, bpm: 120, beatsPerBar: 4),
            TempoSection(startSeconds: 10, bpm: 120, beatsPerBar: 4)
        ])
        // 9.9 s rounds toward 10.0, but 10.0 belongs to section 2 -> clamp to section 1's last beat (9.5).
        let nearest = try XCTUnwrap(map.nearestBeat(toSeconds: 9.9, itemDuration: 100))
        XCTAssertLessThan(nearest, 10.0)
        XCTAssertEqual(nearest, 9.5, accuracy: 1e-9)
    }

    // MARK: - Pure transforms

    func test_splitting_emptyMap_seedsAWholeItemSection() {
        let map = TempoMap().splitting(atSeconds: 30)
        XCTAssertEqual(map.sections.count, 1)
        XCTAssertEqual(map.sections.first?.startSeconds, 0)
    }

    func test_splitting_keepsTheBeatGridContinuousAcrossTheCut() {
        // 100 BPM, 4/4: beat 0.6 s, bar 2.4 s. Split at 5.0 s (not on a grid line).
        let original = TempoMap.singleSection(bpm: 100, beatsPerBar: 4)
        let split = original.splitting(atSeconds: 5.0)
        XCTAssertEqual(split.sections.count, 2)
        // Beats around the cut should be the same set whether or not the section boundary exists.
        let before = original.beatTimes(in: 4...6, itemDuration: 20).map(\.time)
        let after = split.beatTimes(in: 4...6, itemDuration: 20).map(\.time)
        XCTAssertEqual(before.map { ($0 * 1e6).rounded() / 1e6 }, after.map { ($0 * 1e6).rounded() / 1e6 })
    }

    func test_splitting_onAnExistingBoundary_isANoOp() {
        let map = TempoMap(sections: [
            TempoSection(startSeconds: 0, bpm: 120),
            TempoSection(startSeconds: 10, bpm: 140)
        ])
        XCTAssertEqual(map.splitting(atSeconds: 10), map)
        XCTAssertEqual(map.splitting(atSeconds: 0), map)
    }

    func test_removingSection_mergesItsSpanIntoThePrevious() {
        let map = TempoMap(sections: [
            TempoSection(startSeconds: 0, bpm: 120),
            TempoSection(startSeconds: 10, bpm: 140),
            TempoSection(startSeconds: 20, bpm: 90)
        ])
        let removed = map.removingSection(map.sections[1].id)
        XCTAssertEqual(removed.sections.map(\.startSeconds), [0, 20])
        XCTAssertEqual(removed.sectionEndSeconds(for: removed.sections[0], itemDuration: 100), 20)
    }

    func test_removingFirstSection_promotesTheNextToZero() {
        let map = TempoMap(sections: [
            TempoSection(startSeconds: 0, bpm: 120),
            TempoSection(startSeconds: 10, bpm: 140)
        ])
        let removed = map.removingSection(map.sections[0].id)
        XCTAssertEqual(removed.sections.count, 1)
        XCTAssertEqual(removed.sections.first?.startSeconds, 0)
        XCTAssertEqual(removed.sections.first?.bpm, 140)
    }

    func test_removingOnlySection_yieldsEmptyMap() {
        let map = TempoMap.singleSection(bpm: 120)
        XCTAssertTrue(map.removingSection(map.sections[0].id).isEmpty)
    }

    func test_updatingSection_changesFieldsAndRenormalizes() {
        let map = TempoMap(sections: [
            TempoSection(startSeconds: 0, bpm: 120, beatsPerBar: 4),
            TempoSection(startSeconds: 10, bpm: 120, beatsPerBar: 4)
        ])
        let updated = map.updatingSection(map.sections[1].id, bpm: 90, beatsPerBar: 3)
        XCTAssertEqual(updated.sections[1].bpm, 90)
        XCTAssertEqual(updated.sections[1].beatsPerBar, 3)
        // Editing the first section's startSeconds is a no-op (always pinned to 0).
        let pinned = map.updatingSection(map.sections[0].id, startSeconds: 5)
        XCTAssertEqual(pinned.sections[0].startSeconds, 0)
    }

    func test_addingSection_emptyMap_seedsWholeItem_nonEmpty_splits() {
        XCTAssertEqual(TempoMap().addingSection(atSeconds: 99).sections.count, 1)
        let map = TempoMap.singleSection(bpm: 120)
        XCTAssertEqual(map.addingSection(atSeconds: 30).sections.count, 2)
    }
}
