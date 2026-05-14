import Foundation

/// Seed keys understood by the `#if DEBUG` launch handler in `OnlyCueApp`.
/// The test passes `--ui-test-seed=<rawValue>` as a launch argument; the app
/// builds the corresponding `CueListDocument` in its own (unsandboxed) process,
/// writes it to its own temp dir, and opens it via `NSDocumentController`.
///
/// This indirection exists because:
/// - macOS XCTRunner runs UI test bundles inside an App-Sandbox container.
/// - Creating `.withSecurityScope` bookmarks fails inside that sandbox.
/// - Spawning `swift` to escape the sandbox also fails — `xcrun` refuses to
///   run with any sandbox ancestor.
///
/// So the seed creation MUST happen in the unsandboxed app process. The test
/// only names the seed; the app builds it.
///
/// Spec: `docs/superpowers/specs/2026-05-14-ui-test-seed-mechanism-design.md`.
enum SeedKey: String {
    case threeCuesAt1And3And6 = "three-cues-1-3-6"
    case threeCuesAt1And3And6With120BPM = "three-cues-1-3-6-with-120bpm-tempo"

    var launchArgument: String { "--ui-test-seed=\(rawValue)" }
}
