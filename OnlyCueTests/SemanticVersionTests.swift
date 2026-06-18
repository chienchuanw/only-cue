import XCTest
@testable import OnlyCue

/// #565 — the pure version core behind Check for Updates.
final class SemanticVersionTests: XCTestCase {

    func test_parse_fullTriple() {
        XCTAssertEqual(SemanticVersion("1.2.3"), SemanticVersion(major: 1, minor: 2, patch: 3))
    }

    func test_parse_stripsLeadingV() {
        XCTAssertEqual(SemanticVersion("v0.6.0"), SemanticVersion(major: 0, minor: 6, patch: 0))
        XCTAssertEqual(SemanticVersion("V2.0.1"), SemanticVersion(major: 2, minor: 0, patch: 1))
    }

    func test_parse_missingPatch_defaultsToZero() {
        XCTAssertEqual(SemanticVersion("0.6"), SemanticVersion(major: 0, minor: 6, patch: 0))
        XCTAssertEqual(SemanticVersion("3"), SemanticVersion(major: 3, minor: 0, patch: 0))
    }

    func test_parse_dropsPrereleaseAndBuildSuffix() {
        XCTAssertEqual(SemanticVersion("1.2.3-dev"), SemanticVersion(major: 1, minor: 2, patch: 3))
        XCTAssertEqual(SemanticVersion("0.6.0+abc123"), SemanticVersion(major: 0, minor: 6, patch: 0))
    }

    func test_parse_invalid_returnsNil() {
        XCTAssertNil(SemanticVersion(""))
        XCTAssertNil(SemanticVersion("abc"))
        XCTAssertNil(SemanticVersion("1.x.0"))
        XCTAssertNil(SemanticVersion("1.2.3.4"))
    }

    func test_ordering() {
        // numeric, not lexical (1.2 < 1.10)
        XCTAssertLessThan(SemanticVersion(major: 1, minor: 2, patch: 0), SemanticVersion(major: 1, minor: 10, patch: 0))
        XCTAssertLessThan(SemanticVersion(major: 1, minor: 0, patch: 0), SemanticVersion(major: 2, minor: 0, patch: 0))
        XCTAssertLessThan(SemanticVersion(major: 1, minor: 2, patch: 3), SemanticVersion(major: 1, minor: 2, patch: 4))
        XCTAssertGreaterThan(SemanticVersion(major: 0, minor: 6, patch: 0), SemanticVersion(major: 0, minor: 5, patch: 0))
    }

    func test_equality_and_description() {
        XCTAssertEqual(SemanticVersion("0.5.0"), SemanticVersion("v0.5.0"))
        XCTAssertEqual(SemanticVersion(major: 0, minor: 5, patch: 0).description, "0.5.0")
    }
}
