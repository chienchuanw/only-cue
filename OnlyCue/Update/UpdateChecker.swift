import Foundation

/// Outcome of a "Check for Updates" run (#565).
enum UpdateCheckResult: Equatable {
    case updateAvailable(GitHubRelease)
    case upToDate(current: SemanticVersion)
    case runningNewerBuild(current: SemanticVersion, latest: SemanticVersion)
    case failed(message: String)
}

/// Checks the latest GitHub release against the running version. The version
/// decision (`evaluate`) is pure and unit-tested; the single network fetch is
/// the impure boundary and is injectable so tests never hit the network (#565).
struct UpdateChecker {

    static let releasesLatestURL = URL(
        string: "https://api.github.com/repos/chienchuanw/only-cue/releases/latest"
    )!

    var currentVersion: SemanticVersion?
    var fetchLatest: () async throws -> GitHubRelease

    init(
        currentVersion: SemanticVersion? = AppVersion.current,
        fetchLatest: @escaping () async throws -> GitHubRelease = Self.fetchFromGitHub
    ) {
        self.currentVersion = currentVersion
        self.fetchLatest = fetchLatest
    }

    func checkForUpdate() async -> UpdateCheckResult {
        guard let current = currentVersion else {
            return .failed(message: "Could not read the app version.")
        }
        do {
            let release = try await fetchLatest()
            guard let latest = release.version else {
                return .failed(message: "Could not read the latest release version.")
            }
            return Self.evaluate(current: current, latest: latest, release: release)
        } catch {
            return .failed(message: Self.friendlyMessage(for: error))
        }
    }

    /// Pure decision: newer release → update; older → dev build; equal → current.
    static func evaluate(
        current: SemanticVersion,
        latest: SemanticVersion,
        release: GitHubRelease
    ) -> UpdateCheckResult {
        if latest > current { return .updateAvailable(release) }
        if current > latest { return .runningNewerBuild(current: current, latest: latest) }
        return .upToDate(current: current)
    }

    // MARK: - Network boundary

    enum UpdateCheckError: Error { case badStatus(Int) }

    static func fetchFromGitHub() async throws -> GitHubRelease {
        var request = URLRequest(url: releasesLatestURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        // GitHub rejects User-Agent-less API requests with 403.
        request.setValue("OnlyCue", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UpdateCheckError.badStatus(-1)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw UpdateCheckError.badStatus(http.statusCode)
        }
        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    static func friendlyMessage(for error: Error) -> String {
        if case UpdateCheckError.badStatus(let code) = error {
            if code == 403 {
                return "GitHub rate limit reached. Please try again later."
            }
            return "GitHub returned an unexpected response (HTTP \(code))."
        }
        if error is DecodingError {
            return "The release information couldn't be read."
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return "No network connection. Check your internet and try again."
        }
        return "Something went wrong while checking for updates."
    }
}
