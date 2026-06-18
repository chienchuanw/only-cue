import Foundation

/// A downloadable asset attached to a GitHub release. Top-level (not nested in
/// `GitHubRelease`) so its `CodingKeys` stays within SwiftLint's nesting depth.
struct GitHubReleaseAsset: Codable, Equatable {
    let name: String
    let browserDownloadURL: URL

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}

/// The subset of GitHub's `releases/latest` payload OnlyCue needs (#565).
struct GitHubRelease: Codable, Equatable {

    let tagName: String
    let name: String?
    let body: String?
    let htmlURL: URL
    let assets: [GitHubReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlURL = "html_url"
        case assets
    }

    /// The release's version, parsed from its tag.
    var version: SemanticVersion? { SemanticVersion(tagName) }

    /// What "Download" opens: the first `.dmg` asset, or the release page when no
    /// DMG is attached.
    var downloadURL: URL {
        assets.first { $0.name.lowercased().hasSuffix(".dmg") }?.browserDownloadURL ?? htmlURL
    }
}
