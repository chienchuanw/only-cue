import Foundation

/// Builds a `.cuelist` JSON on disk for UI tests, pointing at a bundled silent
/// audio fixture so the launched app's real `AVPlayer` populates `loadedDuration`
/// and the waveform overlay renders. UI test bundles run in a separate process
/// from the app and cannot `@testable import OnlyCue`, so the schema is hand-
/// rolled here against the v11 `ProjectModel` shape. Keep in sync if the schema
/// migrates.
///
/// See `docs/superpowers/specs/2026-05-14-ui-test-seed-mechanism-design.md`.
enum SeedDocumentBuilder {

    private static let schemaVersion = 11
    private static let defaultTypeID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private static let defaultMediaItemID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    private static let fixtureResource = "silent-30s"
    private static let fixtureExtension = "m4a"
    private static let fixtureDuration: TimeInterval = 30

    struct CueSeed {
        let time: TimeInterval
        let bpm: Double?
        let beatsPerBar: Int?

        init(time: TimeInterval, bpm: Double? = nil, beatsPerBar: Int? = nil) {
            self.time = time
            self.bpm = bpm
            self.beatsPerBar = beatsPerBar
        }
    }

    enum BuildError: Error {
        case fixtureNotFound
    }

    /// Writes a `.cuelist` to a fresh temp path and returns the path. The caller
    /// passes the path as a launch argument to `XCUIApplication`; macOS routes
    /// it through `application(_:openURLs:)` and SwiftUI's `DocumentGroup` opens
    /// it. The temp file is left in `NSTemporaryDirectory` for post-mortem
    /// inspection on failure.
    static func writeSeedDocument(
        named name: String,
        cues: [CueSeed],
        bundle: Bundle
    ) throws -> URL {
        guard let fixtureURL = bundle.url(forResource: fixtureResource, withExtension: fixtureExtension) else {
            throw BuildError.fixtureNotFound
        }
        let bookmark = try fixtureURL.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        let json = makeProjectJSON(name: name, cues: cues, bookmark: bookmark)
        let data = try JSONSerialization.data(
            withJSONObject: json,
            options: [.prettyPrinted, .sortedKeys]
        )
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("uitest-\(UUID().uuidString).cuelist")
        try data.write(to: outputURL)
        return outputURL
    }

    /// Catalog: three cues at 1s / 3s / 6s on the silent fixture.
    static func writeThreeCues_1_3_6(bundle: Bundle) throws -> URL {
        try writeSeedDocument(
            named: "Three Cues",
            cues: [
                CueSeed(time: 1),
                CueSeed(time: 3),
                CueSeed(time: 6)
            ],
            bundle: bundle
        )
    }

    /// Catalog: three cues + a 120 BPM cue at t=0 so the derived tempo grid is
    /// active.
    static func writeThreeCuesWith120BPM(bundle: Bundle) throws -> URL {
        try writeSeedDocument(
            named: "Three Cues + 120 BPM",
            cues: [
                CueSeed(time: 0, bpm: 120, beatsPerBar: 4),
                CueSeed(time: 1),
                CueSeed(time: 3),
                CueSeed(time: 6)
            ],
            bundle: bundle
        )
    }

    // MARK: - JSON shape

    private static func makeProjectJSON(
        name: String,
        cues: [CueSeed],
        bookmark: Data
    ) -> [String: Any] {
        [
            "schemaVersion": schemaVersion,
            "id": UUID().uuidString.uppercased(),
            "name": name,
            "cuePointTypes": [
                [
                    "id": defaultTypeID.uuidString.uppercased(),
                    "name": "General",
                    "colorHex": "#4ECDC4",
                    "defaultFadeTime": 0,
                    "defaultNamePattern": "Cue",
                    "isVisible": true,
                    "isExportEnabled": true
                ]
            ],
            "items": [
                makeItemJSON(cues: cues, bookmark: bookmark)
            ],
            "activeItemID": defaultMediaItemID.uuidString.uppercased(),
            "timecodeSettings": [
                "framerate": "30"
            ]
        ]
    }

    private static func makeItemJSON(cues: [CueSeed], bookmark: Data) -> [String: Any] {
        [
            "id": defaultMediaItemID.uuidString.uppercased(),
            "media": [
                "displayName": "\(fixtureResource).\(fixtureExtension)",
                "kind": "audio",
                "duration": fixtureDuration,
                "bookmarkData": bookmark.base64EncodedString()
            ],
            "cues": cues.map(makeCueJSON),
            "startTimecodeFrames": 0,
            "ltcMuted": false
        ]
    }

    private static func makeCueJSON(_ cue: CueSeed) -> [String: Any] {
        var json: [String: Any] = [
            "id": UUID().uuidString.uppercased(),
            "typeID": defaultTypeID.uuidString.uppercased(),
            "name": "",
            "time": cue.time,
            "notes": "",
            "fadeTime": ["fadeIn": 0, "fadeOut": 0]
        ]
        if let bpm = cue.bpm {
            json["bpm"] = bpm
        }
        if let beatsPerBar = cue.beatsPerBar {
            json["beatsPerBar"] = beatsPerBar
        }
        return json
    }
}
