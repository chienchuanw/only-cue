import XCTest
@testable import OnlyCue

/// Coverage for `LTCTickGenerator.ticks`: emits `(xPosition, label, isMajor)`
/// tuples starting at the item's start TC and incrementing by `bucketSeconds`.
/// Labels formatted `HH:MM:SS` (no frames). Pure — exposed for the strip view.
final class LTCTickGeneratorTests: XCTestCase {

    func test_generates_ticksStartingAtItemStartTC_atGivenBucket() {
        let ticks = LTCTickGenerator.ticks(
            duration: 10,
            framerate: .fps25,
            startTimecodeFrames: 90_000,        // 01:00:00:00 @ 25
            bucketSeconds: 5,
            contentWidth: 1_000
        )
        XCTAssertEqual(ticks.count, 3)          // 0, 5, 10 seconds
        XCTAssertEqual(ticks[0].label, "01:00:00")
        XCTAssertEqual(ticks[1].label, "01:00:05")
        XCTAssertEqual(ticks[2].label, "01:00:10")
    }

    func test_xPositionsAreLinearAcrossContentWidth() {
        let ticks = LTCTickGenerator.ticks(
            duration: 10,
            framerate: .fps30,
            startTimecodeFrames: 0,
            bucketSeconds: 5,
            contentWidth: 1_000
        )
        XCTAssertEqual(ticks[0].xPosition, 0, accuracy: 0.001)
        XCTAssertEqual(ticks[1].xPosition, 500, accuracy: 0.001)
        XCTAssertEqual(ticks[2].xPosition, 1_000, accuracy: 0.001)
    }

    func test_majorTickEveryFifthLabel() {
        let ticks = LTCTickGenerator.ticks(
            duration: 30,
            framerate: .fps30,
            startTimecodeFrames: 0,
            bucketSeconds: 1,
            contentWidth: 3_000
        )
        XCTAssertTrue(ticks[0].isMajor)
        XCTAssertFalse(ticks[1].isMajor)
        XCTAssertFalse(ticks[4].isMajor)
        XCTAssertTrue(ticks[5].isMajor)
        XCTAssertTrue(ticks[10].isMajor)
    }

    func test_zeroDurationOrWidth_yieldsEmpty() {
        let zeroDuration = LTCTickGenerator.ticks(
            duration: 0,
            framerate: .fps30,
            startTimecodeFrames: 0,
            bucketSeconds: 1,
            contentWidth: 100
        )
        XCTAssertEqual(zeroDuration.count, 0)

        let zeroWidth = LTCTickGenerator.ticks(
            duration: 10,
            framerate: .fps30,
            startTimecodeFrames: 0,
            bucketSeconds: 1,
            contentWidth: 0
        )
        XCTAssertEqual(zeroWidth.count, 0)
    }

    func test_zeroBucketSeconds_yieldsEmpty() {
        let result = LTCTickGenerator.ticks(
            duration: 10,
            framerate: .fps30,
            startTimecodeFrames: 0,
            bucketSeconds: 0,
            contentWidth: 100
        )
        XCTAssertEqual(result.count, 0)
    }
}
