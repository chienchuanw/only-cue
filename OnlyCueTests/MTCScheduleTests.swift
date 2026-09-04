import XCTest
@testable import OnlyCue

/// Timing-plan tests for `MTCSchedule` (epic #794) — the pure half of the MTC
/// generator, and the reason `MTCOutput` can stay a thin, untested edge.
///
/// A fixed `anchorHostTime` and `ticksPerSecond` are injected throughout, so
/// every expectation is an exact byte/timestamp pair. Nothing here sleeps or
/// reads a real clock.
final class MTCScheduleTests: XCTestCase {

    /// Nanosecond-shaped ticks — keeps the arithmetic readable in expectations.
    private let ticksPerSecond: Double = 1_000_000_000
    private let anchor: UInt64 = 1_000_000_000

    private func schedule(
        _ hours: Int = 1,
        _ minutes: Int = 0,
        _ seconds: Int = 0,
        _ frames: Int = 0,
        rate: SMPTEFramerate = .fps25
    ) throws -> MTCSchedule {
        let timecode = try XCTUnwrap(
            Timecode(hours: hours, minutes: minutes, seconds: seconds, frames: frames, rate: rate)
        )
        return MTCSchedule(startTimecode: timecode, anchorHostTime: anchor, ticksPerSecond: ticksPerSecond)
    }

    // MARK: - Cadence

    // 25 fps → 100 quarter-frames per second → one every 10 ms.
    func test_quarterFrameInterval_isAQuarterOfAFrame() throws {
        XCTAssertEqual(try schedule(rate: .fps25).ticksPerQuarterFrame, 10_000_000, accuracy: 1)
        XCTAssertEqual(try schedule(rate: .fps30).ticksPerQuarterFrame, 8_333_333, accuracy: 1)
        XCTAssertEqual(try schedule(rate: .fps30drop).ticksPerQuarterFrame, 8_333_333, accuracy: 1)
        XCTAssertEqual(try schedule(rate: .fps24).ticksPerQuarterFrame, 10_416_666, accuracy: 1)
    }

    // MARK: - Batch contents

    func test_batch_emitsEightPiecesOfTheStartTimecodeInOrder() throws {
        let plan = try schedule(1, 0, 0, 0, rate: .fps25)
        let messages = plan.batch(from: anchor, until: anchor + 80_000_000)   // exactly 8 × 10 ms

        XCTAssertEqual(messages.count, 8)
        let start = try XCTUnwrap(Timecode(hours: 1, minutes: 0, seconds: 0, frames: 0, rate: .fps25))
        for (index, message) in messages.enumerated() {
            XCTAssertEqual(
                message.byte,
                MTCFrame.quarterFrameByte(piece: index, timecode: start),
                "piece \(index)"
            )
            XCTAssertEqual(message.timestamp, anchor + UInt64(index) * 10_000_000, "piece \(index)")
        }
    }

    // A full eight-message sequence spans two frames, so the value transmitted
    // advances by 2 — never by 1 — from one sequence to the next.
    func test_batch_advancesTimecodeByTwoFramesPerSequence() throws {
        let plan = try schedule(1, 0, 0, 0, rate: .fps25)
        let messages = plan.batch(from: anchor, until: anchor + 240_000_000)   // 24 quarter-frames

        XCTAssertEqual(messages.count, 24)
        let expectedFrames = [0, 2, 4]
        for sequence in 0..<3 {
            let timecode = try XCTUnwrap(
                Timecode(hours: 1, minutes: 0, seconds: 0, frames: expectedFrames[sequence], rate: .fps25)
            )
            for piece in 0..<8 {
                XCTAssertEqual(
                    messages[sequence * 8 + piece].byte,
                    MTCFrame.quarterFrameByte(piece: piece, timecode: timecode),
                    "sequence \(sequence) piece \(piece)"
                )
            }
        }
    }

    // v1 transmits the value uncompensated: the sequence beginning at frame N
    // carries N, and the receiver applies the two-frame assembly offset itself.
    // Pinned deliberately — this is the knob to turn if hardware reads early.
    func test_batch_transmitsUncompensatedTimecode() throws {
        let plan = try schedule(1, 0, 0, 0, rate: .fps25)
        let first = plan.batch(from: anchor, until: anchor + 10_000_000)
        let start = try XCTUnwrap(Timecode(hours: 1, minutes: 0, seconds: 0, frames: 0, rate: .fps25))
        XCTAssertEqual(first.first?.byte, MTCFrame.quarterFrameByte(piece: 0, timecode: start))
    }

    // MARK: - Windowing

    // Consecutive batches must tile the timeline exactly — the half-open window
    // is what stops the refill timer double-sending or gapping the stream.
    func test_batch_windowsAreHalfOpenAndTileExactly() throws {
        let plan = try schedule(1, 0, 0, 0, rate: .fps30)
        let split = anchor + 100_000_000
        let end = anchor + 250_000_000

        let whole = plan.batch(from: anchor, until: end)
        let tiled = plan.batch(from: anchor, until: split) + plan.batch(from: split, until: end)

        XCTAssertEqual(whole, tiled)
        XCTAssertFalse(whole.isEmpty)
    }

    // A window opening before the anchor starts at quarter-frame 0 rather than
    // extrapolating backwards into negative time.
    func test_batch_clampsWindowsOpeningBeforeTheAnchor() throws {
        let plan = try schedule(1, 0, 0, 0, rate: .fps25)
        let messages = plan.batch(from: 0, until: anchor + 20_000_000)

        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages.first?.timestamp, anchor)
    }

    func test_batch_emptyWhenWindowIsEmptyOrInverted() throws {
        let plan = try schedule(1, 0, 0, 0, rate: .fps25)
        XCTAssertTrue(plan.batch(from: anchor, until: anchor).isEmpty)
        XCTAssertTrue(plan.batch(from: anchor + 50_000_000, until: anchor).isEmpty)
    }

    // MARK: - Drop-frame

    // Drop-frame labels come from `Timecode`'s counting rule; the schedule only
    // advances the frame count, so the 00/01 skip at the top of a minute falls
    // out for free.
    func test_batch_dropFrameLabelsFollowTheCountingRule() throws {
        let start = try XCTUnwrap(Timecode(hours: 0, minutes: 0, seconds: 59, frames: 28, rate: .fps30drop))
        let plan = MTCSchedule(startTimecode: start, anchorHostTime: anchor, ticksPerSecond: ticksPerSecond)

        // Second sequence = start + 2 frames, which must land on 00:01:00;02.
        let next = plan.timecode(forSequence: 1)
        XCTAssertEqual(next.displayString, "00:01:00;02")
    }

    // MARK: - Re-anchoring

    // A seek builds a fresh schedule; the piece sequence must restart at 0 so a
    // receiver sees a clean group boundary rather than a truncated one.
    func test_reanchoredSchedule_restartsThePieceSequence() throws {
        let start = try XCTUnwrap(Timecode(hours: 2, minutes: 30, seconds: 15, frames: 10, rate: .fps30))
        let plan = MTCSchedule(startTimecode: start, anchorHostTime: 5_000, ticksPerSecond: ticksPerSecond)
        let first = plan.batch(from: 5_000, until: 5_000 + 8_333_333)

        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(first.first?.byte, MTCFrame.quarterFrameByte(piece: 0, timecode: start))
        XCTAssertEqual(first.first?.timestamp, 5_000)
    }
}
