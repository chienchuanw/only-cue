import XCTest
@testable import OnlyCue

/// #591 — the welcome window's recent-projects rows are derived by this pure
/// mapping over `NSDocumentController.recentDocumentURLs`.
final class RecentProjectsModelTests: XCTestCase {

    private func makeTempFile(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("recent-\(UUID().uuidString)-\(name)")
        try Data([0x00]).write(to: url)
        return url
    }

    func test_recents_derivesNameAndExistsAndPreservesOrder() throws {
        let first = try makeTempFile("alpha.cuelist")
        let second = try makeTempFile("beta.cuelist")
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }

        let rows = RecentProjectsModel.recents(from: [first, second])

        XCTAssertEqual(rows.map(\.url), [first, second], "Order is preserved (newest-first input)")
        XCTAssertEqual(rows[0].name, first.deletingPathExtension().lastPathComponent)
        XCTAssertTrue(rows[0].exists)
        XCTAssertNotNil(rows[0].date)
    }

    func test_recents_marksMissingFileAsNotExisting() {
        let missing = URL(fileURLWithPath: "/no/such/dir/ghost.cuelist")
        let rows = RecentProjectsModel.recents(from: [missing])

        XCTAssertEqual(rows.count, 1, "Missing entries are still listed so they can be removed")
        XCTAssertFalse(rows[0].exists)
        XCTAssertNil(rows[0].date)
        XCTAssertEqual(rows[0].name, "ghost")
    }

    func test_recents_emptyInput_emptyOutput() {
        XCTAssertTrue(RecentProjectsModel.recents(from: []).isEmpty)
    }

    func test_removing_dropsTargetKeepsOrder() {
        let alpha = URL(fileURLWithPath: "/x/a.cuelist")
        let beta = URL(fileURLWithPath: "/x/b.cuelist")
        let gamma = URL(fileURLWithPath: "/x/c.cuelist")

        XCTAssertEqual(RecentProjectsModel.removing(beta, from: [alpha, beta, gamma]), [alpha, gamma])
        XCTAssertEqual(RecentProjectsModel.removing(alpha, from: [alpha, beta, gamma]), [beta, gamma])
    }
}
