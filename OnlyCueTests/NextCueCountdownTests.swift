import XCTest
@testable import OnlyCue

final class NextCueCountdownTests: XCTestCase {

    // MARK: - TransportBar.nextCueInterval

    func test_nextCueInterval_noCues_returnsNil() {
        XCTAssertNil(TransportBar.nextCueInterval(currentTime: 5.0, cues: []))
    }

    func test_nextCueInterval_allCuesPassed_returnsNil() {
        let cues = [makeCue(time: 1.0), makeCue(time: 5.0)]
        XCTAssertNil(TransportBar.nextCueInterval(currentTime: 10.0, cues: cues))
    }

    func test_nextCueInterval_picksNearestFutureCue() throws {
        let cues = [makeCue(time: 5.0), makeCue(time: 12.0), makeCue(time: 20.0)]
        let interval = try XCTUnwrap(TransportBar.nextCueInterval(currentTime: 8.0, cues: cues))
        XCTAssertEqual(interval, 4.0, accuracy: 0.001)
    }

    func test_nextCueInterval_currentTimeBeforeFirstCue_returnsIntervalToFirst() throws {
        let cues = [makeCue(time: 5.0), makeCue(time: 12.0)]
        let interval = try XCTUnwrap(TransportBar.nextCueInterval(currentTime: 0.0, cues: cues))
        XCTAssertEqual(interval, 5.0, accuracy: 0.001)
    }

    func test_nextCueInterval_currentTimeExactlyOnCue_picksNextCue() throws {
        // strictly-greater filter — a cue exactly at currentTime is "now," not "next."
        let cues = [makeCue(time: 5.0), makeCue(time: 10.0)]
        let interval = try XCTUnwrap(TransportBar.nextCueInterval(currentTime: 5.0, cues: cues))
        XCTAssertEqual(interval, 5.0, accuracy: 0.001)
    }

    func test_nextCueInterval_unsortedCues_stillPicksNearest() throws {
        // Cues should be time-sorted in practice, but the helper shouldn't depend on it.
        let cues = [makeCue(time: 20.0), makeCue(time: 5.0), makeCue(time: 12.0)]
        let interval = try XCTUnwrap(TransportBar.nextCueInterval(currentTime: 0.0, cues: cues))
        XCTAssertEqual(interval, 5.0, accuracy: 0.001)
    }

    // MARK: - TimeFormat.compactCountdown

    func test_compactCountdown_subSecond_formatsAsDecisecond() {
        XCTAssertEqual(TimeFormat.compactCountdown(0.0), "0.0")
        XCTAssertEqual(TimeFormat.compactCountdown(0.5), "0.5")
    }

    func test_compactCountdown_subMinute_formatsAsSecondsDecisecond() {
        XCTAssertEqual(TimeFormat.compactCountdown(5.2), "5.2")
        XCTAssertEqual(TimeFormat.compactCountdown(59.9), "59.9")
    }

    func test_compactCountdown_subHour_formatsAsMinutesSecondsDecisecond() {
        XCTAssertEqual(TimeFormat.compactCountdown(60.0), "1:00.0")
        XCTAssertEqual(TimeFormat.compactCountdown(75.5), "1:15.5")
        XCTAssertEqual(TimeFormat.compactCountdown(125.3), "2:05.3")
    }

    func test_compactCountdown_hour_formatsWithHourPrefix() {
        XCTAssertEqual(TimeFormat.compactCountdown(3600.0), "1:00:00.0")
        XCTAssertEqual(TimeFormat.compactCountdown(3725.4), "1:02:05.4")
    }

    func test_compactCountdown_negative_clampsToZero() {
        XCTAssertEqual(TimeFormat.compactCountdown(-5.0), "0.0")
    }

    private func makeCue(time: TimeInterval) -> Cue {
        Cue(
            id: UUID(),
            typeID: UUID(),
            cueNumber: 1,
            name: "test",
            time: time,
            notes: "",
            fadeTime: .zero
        )
    }
}
