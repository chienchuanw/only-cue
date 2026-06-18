import XCTest
@testable import OnlyCue

/// #565 — decode a GitHub `releases/latest` payload and resolve the download URL.
final class GitHubReleaseDecodeTests: XCTestCase {

    private func decode(_ json: String) throws -> GitHubRelease {
        try JSONDecoder().decode(GitHubRelease.self, from: Data(json.utf8))
    }

    func test_decode_picksDmgAsset() throws {
        let json = """
        {
          "tag_name": "v0.6.0",
          "name": "OnlyCue 0.6.0",
          "body": "Release notes here.",
          "html_url": "https://github.com/chienchuanw/only-cue/releases/tag/v0.6.0",
          "draft": false,
          "prerelease": false,
          "assets": [
            { "name": "source.zip", "browser_download_url": "https://example.com/source.zip" },
            { "name": "OnlyCue-0.6.0.dmg", "browser_download_url": "https://example.com/OnlyCue-0.6.0.dmg" }
          ]
        }
        """
        let release = try decode(json)
        XCTAssertEqual(release.tagName, "v0.6.0")
        XCTAssertEqual(release.version, SemanticVersion("0.6.0"))
        XCTAssertEqual(release.body, "Release notes here.")
        XCTAssertEqual(release.downloadURL, URL(string: "https://example.com/OnlyCue-0.6.0.dmg"))
    }

    func test_decode_noDmg_fallsBackToReleasePage() throws {
        let json = """
        {
          "tag_name": "v0.6.0",
          "name": "OnlyCue 0.6.0",
          "body": null,
          "html_url": "https://github.com/chienchuanw/only-cue/releases/tag/v0.6.0",
          "assets": []
        }
        """
        let release = try decode(json)
        XCTAssertNil(release.body)
        XCTAssertEqual(
            release.downloadURL,
            URL(string: "https://github.com/chienchuanw/only-cue/releases/tag/v0.6.0")
        )
    }
}
