import Foundation

/// A `major.minor.patch` version, tolerant of a leading `v` and a
/// pre-release/build suffix (e.g. `v0.6.0`, `0.6`, `1.2.3-dev` → 1.2.3). Pure
/// value type so the update-check decision is unit-testable without the network
/// (#565). Comparison ignores any pre-release suffix — only the numeric core
/// participates.
struct SemanticVersion: Comparable, Equatable, CustomStringConvertible {

    let major: Int
    let minor: Int
    let patch: Int

    init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Parses `"v1.2.3"` / `"1.2.3"` / `"1.2"` (missing patch → 0). Returns nil
    /// for anything without a leading integer-dotted core.
    init?(_ string: String) {
        var trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.first == "v" || trimmed.first == "V" { trimmed.removeFirst() }
        // Drop any pre-release (`-dev`) or build (`+sha`) metadata before parsing.
        let core = trimmed.split(whereSeparator: { $0 == "-" || $0 == "+" }).first.map(String.init) ?? ""
        let parts = core.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard (1...3).contains(parts.count) else { return nil }
        guard let major = Int(parts[0]) else { return nil }
        let minor = parts.count > 1 ? Int(parts[1]) : 0
        let patch = parts.count > 2 ? Int(parts[2]) : 0
        guard let minor, let patch else { return nil }
        self.init(major: major, minor: minor, patch: patch)
    }

    var description: String { "\(major).\(minor).\(patch)" }

    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

/// The running app's version, from `CFBundleShortVersionString`.
enum AppVersion {
    static var currentString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }
    static var current: SemanticVersion? { SemanticVersion(currentString) }
}
