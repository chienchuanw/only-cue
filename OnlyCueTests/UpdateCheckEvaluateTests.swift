import XCTest
@testable import OnlyCue

/// #565 — the pure update-check decision (no network).
final class UpdateCheckEvaluateTests: XCTestCase {

    private func release(tag: String) throws -> GitHubRelease {
        GitHubRelease(
            tagName: tag,
            name: tag,
            body: "notes",
            htmlURL: try XCTUnwrap(URL(string: "https://github.com/chienchuanw/only-cue/releases/tag/\(tag)")),
            assets: []
        )
    }

    func test_evaluate_newerRelease_isUpdateAvailable() throws {
        let rel = try release(tag: "v0.6.0")
        let result = UpdateChecker.evaluate(
            current: SemanticVersion(major: 0, minor: 5, patch: 0),
            latest: SemanticVersion(major: 0, minor: 6, patch: 0),
            release: rel
        )
        XCTAssertEqual(result, .updateAvailable(rel))
    }

    func test_evaluate_equal_isUpToDate() throws {
        let current = SemanticVersion(major: 0, minor: 5, patch: 0)
        let result = UpdateChecker.evaluate(
            current: current,
            latest: SemanticVersion(major: 0, minor: 5, patch: 0),
            release: try release(tag: "v0.5.0")
        )
        XCTAssertEqual(result, .upToDate(current: current))
    }

    func test_evaluate_runningAhead_isRunningNewerBuild() throws {
        let current = SemanticVersion(major: 0, minor: 6, patch: 0)
        let latest = SemanticVersion(major: 0, minor: 5, patch: 0)
        let result = UpdateChecker.evaluate(
            current: current,
            latest: latest,
            release: try release(tag: "v0.5.0")
        )
        XCTAssertEqual(result, .runningNewerBuild(current: current, latest: latest))
    }
}
