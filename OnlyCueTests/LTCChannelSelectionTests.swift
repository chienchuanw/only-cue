import XCTest
@testable import OnlyCue

final class LTCChannelSelectionTests: XCTestCase {

    private func roundTrip(_ value: LTCChannelSelection) throws -> LTCChannelSelection {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(LTCChannelSelection.self, from: data)
    }

    func test_roundTrips_everyCase() throws {
        XCTAssertEqual(try roundTrip(.auto), .auto)
        XCTAssertEqual(try roundTrip(.none), LTCChannelSelection.none)
        XCTAssertEqual(try roundTrip(.channel(0)), .channel(0))
        XCTAssertEqual(try roundTrip(.channel(2)), .channel(2))
    }

    func test_encodesAsAStableStringForm() throws {
        let json = String(data: try JSONEncoder().encode(LTCChannelSelection.channel(2)),
                          encoding: .utf8)
        XCTAssertEqual(json, "\"channel:2\"")
        XCTAssertEqual(String(data: try JSONEncoder().encode(LTCChannelSelection.auto),
                              encoding: .utf8), "\"auto\"")
        XCTAssertEqual(String(data: try JSONEncoder().encode(LTCChannelSelection.none),
                              encoding: .utf8), "\"none\"")
    }

    func test_unknownStringDecodesAsAuto() throws {
        let data = "\"channel:banana\"".data(using: .utf8)!
        XCTAssertEqual(try JSONDecoder().decode(LTCChannelSelection.self, from: data), .auto)
    }
}
