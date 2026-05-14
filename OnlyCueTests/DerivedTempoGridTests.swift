import XCTest
@testable import OnlyCue

final class DerivedTempoGridTests: XCTestCase {

    func testEmptyCueListYieldsEmptyGrid() {
        let grid = DerivedTempoGrid.from(cues: [], itemDuration: 30)
        XCTAssertTrue(grid.isEmpty)
        XCTAssertEqual(grid.beatTimes(in: 0...30, itemDuration: 30).count, 0)
    }

    func testCuesWithoutBPMYieldEmptyGrid() {
        let grid = DerivedTempoGrid.from(
            cues: [makeCue(time: 0), makeCue(time: 5)],
            itemDuration: 30
        )
        XCTAssertTrue(grid.isEmpty)
    }

    func testSingleSegmentBeatsTickFromCueTime() {
        let grid = DerivedTempoGrid.from(
            cues: [makeCue(time: 0, bpm: 120, beatsPerBar: 4)],
            itemDuration: 2.0
        )
        let beats = grid.beatTimes(in: 0...2, itemDuration: 2).map(\.time)
        assertCloseEnough(beats, [0.0, 0.5, 1.0, 1.5, 2.0])
    }

    func testBeatIndexZeroIsDownbeat() {
        let grid = DerivedTempoGrid.from(
            cues: [makeCue(time: 0, bpm: 120, beatsPerBar: 4)],
            itemDuration: 2.0
        )
        let beats = grid.beatTimes(in: 0...2, itemDuration: 2)
        XCTAssertTrue(beats[0].isDownbeat, "cue itself is bar 1 beat 1")
        XCTAssertFalse(beats[1].isDownbeat)
        XCTAssertFalse(beats[2].isDownbeat)
        XCTAssertFalse(beats[3].isDownbeat)
        XCTAssertTrue(beats[4].isDownbeat, "second downbeat at j=4 → t=2.0")
    }

    func testTwoBPMSegments() {
        let grid = DerivedTempoGrid.from(
            cues: [
                makeCue(time: 0, bpm: 120, beatsPerBar: 4),
                makeCue(time: 2.5, bpm: 60, beatsPerBar: 4)
            ],
            itemDuration: 5.0
        )
        let beats = grid.beatTimes(in: 0...5, itemDuration: 5).map(\.time)
        // Seg1 [0,2.5): 120bpm → 0, 0.5, 1.0, 1.5, 2.0 (2.5 belongs to seg2)
        // Seg2 [2.5,5]: 60bpm → 2.5, 3.5, 4.5
        assertCloseEnough(beats, [0.0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.5, 4.5])
    }

    func testBeatsPerBarInheritsFromPreviousSegment() {
        let grid = DerivedTempoGrid.from(
            cues: [
                makeCue(time: 0, bpm: 120, beatsPerBar: 3),
                makeCue(time: 4, bpm: 90, beatsPerBar: nil) // inherit 3
            ],
            itemDuration: 8
        )
        let downbeats = grid.barTimes(in: 0...8, itemDuration: 8)
        // Seg1 120bpm 3/4: beat 0.5, bar 1.5 → 0, 1.5, 3.0 (4.5 past end)
        // Seg2 90bpm 3/4: beat 2/3, bar 2 → 4, 6, 8
        XCTAssertEqual(downbeats[0], 0, accuracy: 1e-9)
        XCTAssertEqual(downbeats[1], 1.5, accuracy: 1e-9)
        XCTAssertEqual(downbeats[2], 3.0, accuracy: 1e-9)
        XCTAssertEqual(downbeats[3], 4.0, accuracy: 1e-9)
    }

    func testDefaultBeatsPerBarIsFourWhenNoneSet() {
        let grid = DerivedTempoGrid.from(
            cues: [makeCue(time: 0, bpm: 120, beatsPerBar: nil)],
            itemDuration: 4
        )
        let downbeats = grid.barTimes(in: 0...4, itemDuration: 4)
        assertCloseEnough(downbeats, [0.0, 2.0, 4.0])
    }

    func testUnsortedInputIsHandled() {
        let grid = DerivedTempoGrid.from(
            cues: [makeCue(time: 2.5, bpm: 60), makeCue(time: 0, bpm: 120)],
            itemDuration: 5
        )
        XCTAssertFalse(grid.isEmpty)
        XCTAssertEqual(grid.beatTimes(in: 0...5, itemDuration: 5).first?.time, 0)
    }

    func testNearestBeatClampsIntoSegment() throws {
        let grid = DerivedTempoGrid.from(
            cues: [
                makeCue(time: 0, bpm: 120, beatsPerBar: 4),
                makeCue(time: 2.5, bpm: 60, beatsPerBar: 4)
            ],
            itemDuration: 5
        )
        // 2.3s: closer to 2.5 (segment 2 boundary) than 2.0 (seg1 last beat).
        XCTAssertEqual(try XCTUnwrap(grid.nearestBeat(toSeconds: 2.3, itemDuration: 5)), 2.5, accuracy: 1e-9)
        // 2.05s: closer to 2.0 (still in seg1).
        XCTAssertEqual(try XCTUnwrap(grid.nearestBeat(toSeconds: 2.05, itemDuration: 5)), 2.0, accuracy: 1e-9)
    }

    func testNearestBarReturnsDownbeat() throws {
        let grid = DerivedTempoGrid.from(
            cues: [makeCue(time: 0, bpm: 120, beatsPerBar: 4)],
            itemDuration: 4
        )
        XCTAssertEqual(try XCTUnwrap(grid.nearestBar(toSeconds: 1.9, itemDuration: 4)), 2.0, accuracy: 1e-9)
    }

    // MARK: - Helpers

    private func makeCue(time: TimeInterval, bpm: Double? = nil, beatsPerBar: Int? = nil) -> Cue {
        Cue(
            id: UUID(),
            typeID: UUID(),
            cueNumber: nil,
            name: "",
            time: time,
            notes: "",
            fadeTime: .zero,
            bpm: bpm,
            beatsPerBar: beatsPerBar
        )
    }

    private func assertCloseEnough(
        _ lhs: [Double],
        _ rhs: [Double],
        accuracy: Double = 1e-9,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        XCTAssertEqual(lhs.count, rhs.count, file: file, line: line)
        zip(lhs, rhs).forEach { XCTAssertEqual($0, $1, accuracy: accuracy, file: file, line: line) }
    }
}
