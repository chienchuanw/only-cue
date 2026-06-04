#if DEBUG
import AppKit
import Foundation

/// `#if DEBUG`-only launch handler that lets UI tests open a pre-seeded
/// document. Trigger: pass `--ui-test-seed=<key>` as a launch argument.
///
/// This indirection exists because:
/// - macOS UI test runners (`XCTRunner`) execute inside an App-Sandbox
///   container, so the test process cannot create `.withSecurityScope`
///   bookmarks or spawn `swift`/`xcrun` to do so.
/// - `Bookmarks.resolve` in production requires `.withSecurityScope`, so plain
///   bookmarks from the test would not survive the round-trip.
///
/// Therefore the seed JSON is constructed in the (unsandboxed) app process,
/// bookmarking a fixture that ships in the app bundle. The handler writes the
/// resulting `.cuelist` to `NSTemporaryDirectory` and asks `NSDocumentController`
/// to open it, which is the same path `/usr/bin/open` would trigger.
///
/// Production builds skip this file entirely (`#if DEBUG`).
///
/// The seed *plan* (which media items / cues / lyrics each key produces) lives
/// in `UITestSeedHandler+Plan.swift`; this file owns launch + document IO.
enum UITestSeedHandler {

    private static let argumentPrefix = "--ui-test-seed="
    private nonisolated(unsafe) static var didOpen = false

    /// Called at app launch. If a seed-arg is present and recognized, opens
    /// the seeded document; otherwise no-ops. `App.init` can fire multiple
    /// times during SwiftUI's scene-init lifecycle, so the seed is opened
    /// at most once per process.
    @MainActor
    static func openSeededDocumentIfRequested() {
        guard !didOpen else { return }
        didOpen = true
        guard let key = parseSeedKey(from: CommandLine.arguments) else { return }
        do {
            let url = try writeSeedDocument(for: key)
            NSDocumentController.shared.openDocument(
                withContentsOf: url,
                display: true,
                completionHandler: { _, _, _ in }
            )
        } catch {
            FileHandle.standardError.write(Data("UITestSeedHandler error: \(error)\n".utf8))
        }
    }

    // MARK: - Document IO

    private static func parseSeedKey(from arguments: [String]) -> String? {
        for arg in arguments where arg.hasPrefix(argumentPrefix) {
            return String(arg.dropFirst(argumentPrefix.count))
        }
        return nil
    }

    private static func writeSeedDocument(for key: String) throws -> URL {
        let project = try buildProject(for: key)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(project)
        let outURL = try outputURL(for: key)
        try data.write(to: outURL)
        return outURL
    }

    /// Where the seeded `.cuelist` is written. Populated seeds get a named file
    /// inside a unique temp subdir so the document window title matches the
    /// Figma reference (e.g. "Set List — Act I"); legacy seeds keep the flat
    /// `seed-<uuid>.cuelist` path their tests have always used.
    private static func outputURL(for key: String) throws -> URL {
        guard let name = documentBaseName(for: key) else {
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("seed-\(UUID().uuidString).cuelist")
        }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("seed-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(name).cuelist")
    }

    /// Builds the seeded `ProjectModel` end-to-end — staging each item's bundled
    /// fixture and creating its security-scoped bookmark. Internal so unit tests
    /// can exercise the real fixture/bookmark path in the (unsandboxed) app host.
    static func buildProject(for key: String) throws -> ProjectModel {
        let types = cueTypes(for: key)
        let seeds = try itemSeeds(for: key)
        var items: [MediaItem] = []
        var activeID: UUID?
        for seed in seeds {
            let res = seed.fixture.resource
            let bookmark = try stageFixtureBookmark(name: res.name, ext: res.ext)
            let itemID = UUID()
            if seed.isActive { activeID = itemID }
            items.append(
                MediaItem(
                    id: itemID,
                    media: MediaReference(
                        displayName: seed.displayName,
                        kind: seed.kind,
                        duration: seed.duration,
                        bookmarkData: bookmark
                    ),
                    cues: seed.cues.map { cue($0, types: types) },
                    lyrics: seed.lyrics
                )
            )
        }
        return ProjectModel(
            schemaVersion: ProjectModel.currentSchemaVersion,
            id: UUID(),
            name: documentBaseName(for: key) ?? "UITestSeed:\(key)",
            cuePointTypes: types,
            items: items,
            activeItemID: activeID ?? items.first?.id
        )
    }

    private static func cue(_ spec: CueSpec, types: [CuePointType]) -> Cue {
        Cue(
            id: UUID(),
            typeID: types[min(max(0, spec.typeIndex), types.count - 1)].id,
            cueNumber: spec.cueNumber,
            name: spec.name,
            time: spec.time,
            notes: "",
            fadeTime: spec.fadeTime,
            bpm: spec.bpm,
            beatsPerBar: spec.beatsPerBar
        )
    }

    /// Copies a bundled fixture into a unique tmp path and returns a
    /// security-scoped bookmark for it. Staging-then-bookmarking insulates the
    /// resulting `.cuelist` from App Translocation / DerivedData cleanup.
    private static func stageFixtureBookmark(name: String, ext: String) throws -> Data {
        guard let fixtureURL = Bundle.main.url(forResource: name, withExtension: ext) else {
            throw NSError(
                domain: "UITestSeedHandler",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey: "Bundled UI-test fixture not found: \(name).\(ext)"
                ]
            )
        }
        let stagedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("seed-\(UUID().uuidString)-\(name).\(ext)")
        try? FileManager.default.removeItem(at: stagedURL)
        try FileManager.default.copyItem(at: fixtureURL, to: stagedURL)
        return try Bookmarks.create(for: stagedURL)
    }
}
#endif
