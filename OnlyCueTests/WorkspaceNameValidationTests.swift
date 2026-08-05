import XCTest
@testable import OnlyCue

final class WorkspaceNameValidationTests: XCTestCase {

    private let existing = ["Default", "Focus", "Wide"]

    func test_validName_isAccepted() {
        XCTAssertNil(WorkspaceNameValidator.validate("Tight", existingNames: existing, allowing: nil))
    }

    func test_emptyName_isRejected() {
        XCTAssertEqual(
            WorkspaceNameValidator.validate("", existingNames: existing, allowing: nil),
            .empty
        )
    }

    func test_whitespaceOnlyName_isRejected() {
        XCTAssertEqual(
            WorkspaceNameValidator.validate("   \n", existingNames: existing, allowing: nil),
            .empty
        )
    }

    func test_theReservedDefaultName_isRejected() {
        XCTAssertEqual(
            WorkspaceNameValidator.validate("Default", existingNames: existing, allowing: nil),
            .reserved
        )
    }

    func test_duplicateName_isRejected() {
        XCTAssertEqual(
            WorkspaceNameValidator.validate("Focus", existingNames: existing, allowing: nil),
            .duplicate
        )
    }

    func test_renamingAPresetToItsOwnName_isAccepted() {
        // Opening Rename and pressing Save without editing must not error.
        XCTAssertNil(
            WorkspaceNameValidator.validate("Focus", existingNames: existing, allowing: "Focus")
        )
    }

    func test_surroundingWhitespace_isTrimmedBeforeComparison() {
        XCTAssertEqual(
            WorkspaceNameValidator.validate("  Focus  ", existingNames: existing, allowing: nil),
            .duplicate
        )
    }

    func test_everyProblem_hasANonEmptyMessage() {
        for problem in [WorkspaceNameProblem.empty, .reserved, .duplicate] {
            XCTAssertFalse(problem.message.isEmpty, "\(problem) needs a message")
        }
    }
}
