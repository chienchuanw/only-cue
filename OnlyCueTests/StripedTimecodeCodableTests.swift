import XCTest
@testable import OnlyCue

/// Codable round-trip for the LTC value types persisted per song (#754).
final class StripedTimecodeCodableTests: XCTestCase {

    func test_timecode_roundTrips() throws {
        let tc = Timecode(frameCount: 30 * 3661, rate: .fps30) // 01:01:01:00
        let data = try JSONEncoder().encode(tc)
        XCTAssertEqual(try JSONDecoder().decode(Timecode.self, from: data), tc)
    }

    func test_dropFrameTimecode_roundTrips() throws {
        let tc = Timecode(frameCount: 123_456, rate: .fps30drop)
        let data = try JSONEncoder().encode(tc)
        XCTAssertEqual(try JSONDecoder().decode(Timecode.self, from: data), tc)
    }

    func test_stripedTrack_roundTrips() throws {
        let track = StripedTimecodeTrack(
            anchorTimecode: Timecode(frameCount: 108_000, rate: .fps30),
            anchorPlaybackSeconds: 12.5,
            ltcChannel: 1
        )
        let data = try JSONEncoder().encode(track)
        XCTAssertEqual(try JSONDecoder().decode(StripedTimecodeTrack.self, from: data), track)
    }
}
