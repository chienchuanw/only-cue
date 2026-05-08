import XCTest
@testable import OnlyCue

@MainActor
final class CueListDocumentTests: XCTestCase {

    func test_initEmpty_seedsDefaultCuePointType() {
        let document = CueListDocument()

        XCTAssertEqual(document.model.cuePointTypes.count, 1, "new documents must seed exactly one default Type")
        let defaultType = document.model.cuePointTypes.first
        XCTAssertEqual(defaultType?.name, "General")
        XCTAssertEqual(defaultType?.colorHex, "#4ECDC4")
    }
}
