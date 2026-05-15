import SwiftUI
import XCTest
@testable import OnlyCue

final class EnvironmentFramerateTests: XCTestCase {

    func test_default_isFps30() {
        let env = EnvironmentValues()
        XCTAssertEqual(env.projectFramerate, .fps30)
    }

    func test_set_thenGet_roundTrips() {
        var env = EnvironmentValues()
        env.projectFramerate = .fps25
        XCTAssertEqual(env.projectFramerate, .fps25)
        env.projectFramerate = .fps30drop
        XCTAssertEqual(env.projectFramerate, .fps30drop)
    }
}
