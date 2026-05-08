import XCTest
@testable import OnlyCue

final class FadeTimeTests: XCTestCase {

    func test_symmetric_codableRoundTrip() throws {
        let original = FadeTime(fadeIn: 1.5, fadeOut: 1.5)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(FadeTime.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func test_split_codableRoundTrip_preservesIndependentInAndOut() throws {
        let original = FadeTime(fadeIn: 1.0, fadeOut: 2.0)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(FadeTime.self, from: data)
        XCTAssertEqual(decoded.fadeIn, 1.0)
        XCTAssertEqual(decoded.fadeOut, 2.0)
    }
}
