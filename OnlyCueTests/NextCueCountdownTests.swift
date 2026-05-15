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

    // MARK: - TimeFormat.smpteCountdown

    func test_smpteCountdown_subSecond_formatsAsSSColonFF() {
        XCTAssertEqual(TimeFormat.smpteCountdown(0.0, rate: .fps30), "00:00")
        XCTAssertEqual(TimeFormat.smpteCountdown(0.5, rate: .fps30), "00:15")
    }

    func test_smpteCountdown_subMinute_formatsAsSSColonFF() {
        XCTAssertEqual(TimeFormat.smpteCountdown(5.5, rate: .fps30), "05:15")
        XCTAssertEqual(TimeFormat.smpteCountdown(59.9, rate: .fps30), "59:27")
    }

    func test_smpteCountdown_subHour_includesMinute() {
        XCTAssertEqual(TimeFormat.smpteCountdown(60.0, rate: .fps30), "1:00:00")
        XCTAssertEqual(TimeFormat.smpteCountdown(75.5, rate: .fps30), "1:15:15")
        XCTAssertEqual(TimeFormat.smpteCountdown(125.3, rate: .fps30), "2:05:09")
    }

    func test_smpteCountdown_hour_includesHour() {
        XCTAssertEqual(TimeFormat.smpteCountdown(3600.0, rate: .fps30), "1:00:00:00")
        XCTAssertEqual(TimeFormat.smpteCountdown(3725.4, rate: .fps30), "1:02:05:12")
    }

    func test_smpteCountdown_negative_clampsToZero() {
        XCTAssertEqual(TimeFormat.smpteCountdown(-5.0, rate: .fps30), "00:00")
    }

    // MARK: - TransportBar.activeBPM

    func test_activeBPM_noCues_returnsNil() {
        XCTAssertNil(TransportBar.activeBPM(currentTime: 5.0, cues: []))
    }

    func test_activeBPM_noCueWithBPM_returnsNil() {
        let cues = [makeCue(time: 1.0), makeCue(time: 5.0)]
        XCTAssertNil(TransportBar.activeBPM(currentTime: 10.0, cues: cues))
    }

    func test_activeBPM_returnsLatestTempodCueAtOrBeforePlayhead() throws {
        let cues = [
            makeCue(time: 0.0, bpm: 120, beatsPerBar: 4),
            makeCue(time: 10.0, bpm: 90, beatsPerBar: 3),
            makeCue(time: 20.0, bpm: 140, beatsPerBar: 4)
        ]
        let result = try XCTUnwrap(TransportBar.activeBPM(currentTime: 15.0, cues: cues))
        XCTAssertEqual(result.bpm, 90, accuracy: 0.001)
        XCTAssertEqual(result.beatsPerBar, 3)
    }

    func test_activeBPM_includesCueExactlyAtPlayhead() throws {
        // "at or before" — a cue exactly at currentTime supplies the active tempo.
        let cues = [makeCue(time: 5.0, bpm: 100, beatsPerBar: 4)]
        let result = try XCTUnwrap(TransportBar.activeBPM(currentTime: 5.0, cues: cues))
        XCTAssertEqual(result.bpm, 100, accuracy: 0.001)
    }

    func test_activeBPM_skipsCuesWithoutBPM() throws {
        // Latest cue at-or-before is the tempo-less one; activeBPM skips it
        // and returns the earlier tempo'd cue.
        let cues = [
            makeCue(time: 0.0, bpm: 120, beatsPerBar: 4),
            makeCue(time: 10.0)
        ]
        let result = try XCTUnwrap(TransportBar.activeBPM(currentTime: 15.0, cues: cues))
        XCTAssertEqual(result.bpm, 120, accuracy: 0.001)
        XCTAssertEqual(result.beatsPerBar, 4)
    }

    func test_activeBPM_cueWithBPMButNoBeatsPerBar_defaultsTo4() throws {
        // beatsPerBar is independently optional on Cue; missing → 4/4.
        let cues = [makeCue(time: 0.0, bpm: 120, beatsPerBar: nil)]
        let result = try XCTUnwrap(TransportBar.activeBPM(currentTime: 5.0, cues: cues))
        XCTAssertEqual(result.bpm, 120, accuracy: 0.001)
        XCTAssertEqual(result.beatsPerBar, 4)
    }

    // MARK: - TransportBar.beatCountdown

    func test_beatCountdown_atZero_returnsPulseOne() {
        // Non-zero floor — a 0s interval still shows ".pulse(remaining: 1)"
        // so the readout never blanks at the cue boundary.
        let result = TransportBar.beatCountdown(interval: 0.0, bpm: 120, beatsPerBar: 4)
        XCTAssertEqual(result, .pulse(remaining: 1))
    }

    func test_beatCountdown_underOneBar_returnsPulseWithRemainingBeats() {
        // 120 bpm, 4/4 → 1 beat = 0.5s. Interval 1.0s → 2 beats left.
        let result = TransportBar.beatCountdown(interval: 1.0, bpm: 120, beatsPerBar: 4)
        XCTAssertEqual(result, .pulse(remaining: 2))
    }

    func test_beatCountdown_exactlyOneBar_returnsPulseFull() {
        // 120 bpm, 4/4 → 1 bar = 2.0s. Boundary case — still pulse, full bar.
        let result = TransportBar.beatCountdown(interval: 2.0, bpm: 120, beatsPerBar: 4)
        XCTAssertEqual(result, .pulse(remaining: 4))
    }

    func test_beatCountdown_overOneBar_returnsBarsRoundedDown() {
        // 120 bpm, 4/4 → 1 beat = 0.5s. Interval 4.5s → ceil(9) = 9 beats → 9/4 = 2 bars.
        let result = TransportBar.beatCountdown(interval: 4.5, bpm: 120, beatsPerBar: 4)
        XCTAssertEqual(result, .bars(2))
    }

    func test_beatCountdown_wellOverOneBar_returnsBars() {
        // 60 bpm, 4/4 → 1 beat = 1.0s, 1 bar = 4.0s. Interval 13.2s → 14 beats → 3 bars.
        let result = TransportBar.beatCountdown(interval: 13.2, bpm: 60, beatsPerBar: 4)
        XCTAssertEqual(result, .bars(3))
    }

    func test_beatCountdown_threeFourTime_respectsBeatsPerBar() {
        // 90 bpm, 3/4 → 1 beat ≈ 0.6667s, 1 bar = 2.0s. Interval 2.5s → 4 beats → 1 bar.
        let result = TransportBar.beatCountdown(interval: 2.5, bpm: 90, beatsPerBar: 3)
        XCTAssertEqual(result, .bars(1))
    }

    // MARK: - TransportBar.countdownLabel

    func test_countdownLabel_timeMode_formatsAsSMPTECountdown() {
        let label = TransportBar.countdownLabel(
            mode: .time,
            interval: 4.2,
            activeTempo: nil,
            rate: .fps30
        )
        // 4.2s @ 30fps = 4 sec, 6 frames
        XCTAssertEqual(label, "Next: 04:06")
    }

    func test_countdownLabel_beatsMode_underOneBar_formatsAsPulse() {
        // 120 bpm, 4/4, interval 1.0s → 2 beats → pulse. The pure label
        // renders the full bar shape "4 · 3 · 2 · 1"; per-beat emphasis is
        // a view concern, not in this string builder.
        let label = TransportBar.countdownLabel(
            mode: .beats,
            interval: 1.0,
            activeTempo: (bpm: 120, beatsPerBar: 4),
            rate: .fps30
        )
        XCTAssertEqual(label, "Next: 4 · 3 · 2 · 1")
    }

    func test_countdownLabel_beatsMode_overOneBar_formatsAsBars() {
        let label = TransportBar.countdownLabel(
            mode: .beats,
            interval: 4.5,
            activeTempo: (bpm: 120, beatsPerBar: 4),
            rate: .fps30
        )
        XCTAssertEqual(label, "Next: ~2 bars")
    }

    func test_countdownLabel_beatsMode_singleBar_pluralization() {
        // 60 bpm, 4/4 → interval 5.0s → 5 beats > 4 → 1 bar. Singular "bar".
        let label = TransportBar.countdownLabel(
            mode: .beats,
            interval: 5.0,
            activeTempo: (bpm: 60, beatsPerBar: 4),
            rate: .fps30
        )
        XCTAssertEqual(label, "Next: ~1 bar")
    }

    func test_countdownLabel_beatsMode_noActiveTempo_fallsBackToTimePlusHintGlyph() {
        let label = TransportBar.countdownLabel(
            mode: .beats,
            interval: 4.2,
            activeTempo: nil,
            rate: .fps30
        )
        // 4.2s @ 30fps = 4 sec, 6 frames
        XCTAssertEqual(label, "Next: 04:06 ⓘ")
    }

    private func makeCue(
        time: TimeInterval,
        bpm: Double? = nil,
        beatsPerBar: Int? = nil
    ) -> Cue {
        Cue(
            id: UUID(),
            typeID: UUID(),
            cueNumber: 1,
            name: "test",
            time: time,
            notes: "",
            fadeTime: .zero,
            bpm: bpm,
            beatsPerBar: beatsPerBar
        )
    }
}
