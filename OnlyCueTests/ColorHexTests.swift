import SwiftUI
import XCTest
@testable import OnlyCue

final class ColorHexTests: XCTestCase {

    func test_init_parsesValidHex() throws {
        let color = try XCTUnwrap(Color(hex: "#FF0000"))
        let components = NSColor(color).cgColor.components ?? []
        XCTAssertEqual(components[0], 1, accuracy: 0.01)
        XCTAssertEqual(components[1], 0, accuracy: 0.01)
        XCTAssertEqual(components[2], 0, accuracy: 0.01)
    }

    func test_init_acceptsLowercase() {
        XCTAssertNotNil(Color(hex: "#abcdef"))
    }

    func test_init_acceptsWithoutHashPrefix() {
        XCTAssertNotNil(Color(hex: "00FF88"))
    }

    func test_init_rejectsInvalidLength() {
        XCTAssertNil(Color(hex: "#FFF"))
        XCTAssertNil(Color(hex: "#FFFFFFF"))
    }

    func test_init_rejectsNonHex() {
        XCTAssertNil(Color(hex: "#GGGGGG"))
    }
}
