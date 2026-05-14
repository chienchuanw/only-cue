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
enum UITestSeedHandler {

    private static let argumentPrefix = "--ui-test-seed="
    private static let fixtureName = "silent-30s"
    private static let fixtureExtension = "m4a"
    private static let fixtureDuration: TimeInterval = 30
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

    // MARK: - Internals

    private static func parseSeedKey(from arguments: [String]) -> String? {
        for arg in arguments where arg.hasPrefix(argumentPrefix) {
            return String(arg.dropFirst(argumentPrefix.count))
        }
        return nil
    }

    private static func writeSeedDocument(for key: String) throws -> URL {
        let bookmark = try stageFixtureBookmark()
        let project = try buildProject(for: key, bookmark: bookmark)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(project)
        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("seed-\(UUID().uuidString).cuelist")
        try data.write(to: outURL)
        return outURL
    }

    /// Copies the bundled silent fixture into a unique tmp path and returns a
    /// security-scoped bookmark for it. Staging-then-bookmarking insulates the
    /// resulting `.cuelist` from App Translocation / DerivedData cleanup.
    private static func stageFixtureBookmark() throws -> Data {
        guard let fixtureURL = Bundle.main.url(
            forResource: fixtureName,
            withExtension: fixtureExtension
        ) else {
            throw NSError(
                domain: "UITestSeedHandler",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Bundled UI-test fixture not found: \(fixtureName).\(fixtureExtension)"
                ]
            )
        }
        let stagedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("seed-\(UUID().uuidString)-\(fixtureName).\(fixtureExtension)")
        try? FileManager.default.removeItem(at: stagedURL)
        try FileManager.default.copyItem(at: fixtureURL, to: stagedURL)
        return try Bookmarks.create(for: stagedURL)
    }

    private static func buildProject(for key: String, bookmark: Data) throws -> ProjectModel {
        let cues = try cueSeeds(for: key)
        let typeID = UUID()
        let itemID = UUID()
        return ProjectModel(
            schemaVersion: ProjectModel.currentSchemaVersion,
            id: UUID(),
            name: "UITestSeed:\(key)",
            cuePointTypes: [
                CuePointType(id: typeID, name: "General", colorHex: "#4ECDC4")
            ],
            items: [
                MediaItem(
                    id: itemID,
                    media: MediaReference(
                        displayName: "\(fixtureName).\(fixtureExtension)",
                        kind: .audio,
                        duration: fixtureDuration,
                        bookmarkData: bookmark
                    ),
                    cues: cues.map { spec in
                        Cue(
                            id: UUID(),
                            typeID: typeID,
                            cueNumber: nil,
                            name: "",
                            time: spec.time,
                            notes: "",
                            fadeTime: .zero,
                            bpm: spec.bpm,
                            beatsPerBar: spec.beatsPerBar
                        )
                    }
                )
            ],
            activeItemID: itemID
        )
    }

    private struct CueSpec {
        let time: TimeInterval
        let bpm: Double?
        let beatsPerBar: Int?
    }

    private static func cueSeeds(for key: String) throws -> [CueSpec] {
        switch key {
        case "three-cues-1-3-6":
            return [
                CueSpec(time: 1, bpm: nil, beatsPerBar: nil),
                CueSpec(time: 3, bpm: nil, beatsPerBar: nil),
                CueSpec(time: 6, bpm: nil, beatsPerBar: nil)
            ]
        case "three-cues-1-3-6-with-120bpm-tempo":
            return [
                CueSpec(time: 0, bpm: 120, beatsPerBar: 4),
                CueSpec(time: 1, bpm: nil, beatsPerBar: nil),
                CueSpec(time: 3, bpm: nil, beatsPerBar: nil),
                CueSpec(time: 6, bpm: nil, beatsPerBar: nil)
            ]
        default:
            throw NSError(
                domain: "UITestSeedHandler",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Unknown UI-test seed key: \(key)"]
            )
        }
    }
}
#endif
