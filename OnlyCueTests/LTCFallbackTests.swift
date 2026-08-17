import XCTest
@testable import OnlyCue

final class LTCFallbackTests: XCTestCase {

    private func track(_ channel: Int) -> StripedTimecodeTrack {
        StripedTimecodeTrack(
            anchorTimecode: Timecode(frameCount: 108_000, rate: .fps30),
            anchorPlaybackSeconds: 0,
            ltcChannel: channel
        )
    }

    func test_prefersDetected() {
        XCTAssertEqual(LTCFallback.resolve(detected: track(1), remembered: track(2)), track(1))
    }

    func test_fallsBackToRememberedWhenDetectionFails() {
        XCTAssertEqual(LTCFallback.resolve(detected: nil, remembered: track(2)), track(2))
    }

    func test_nilWhenBothAbsent() {
        XCTAssertNil(LTCFallback.resolve(detected: nil, remembered: nil))
    }
}
