import XCTest
@testable import OnlyCue

// MARK: - Contract model

/// Shape of `golden/cuelist-migration-v1.json`. macOS is the source of truth; the
/// C# core in `windows/OnlyCue.Core` only ever reads this file.
struct CuelistMigrationGoldenVector: Codable, Equatable {
    let contract: String
    let version: Int
    let note: String
    let cases: [Case]

    struct Case: Codable, Equatable {
        /// `"v7"` — names the rung so a failing case is identifiable at a glance.
        let name: String
        let schemaVersion: Int
        /// The legacy document verbatim, as a JSON string. Kept opaque so the
        /// bytes a real file would contain are what the port is fed.
        let inputJSON: String
        /// The migrated v23 model, canonicalised (see `CuelistMigrationGolden`).
        let expect: CanonicalJSON
    }
}

// MARK: - Generator

enum CuelistMigrationGolden {

    /// Matches a hyphenated UUID in either case.
    private static let uuidPattern = try? NSRegularExpression(
        pattern: "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"
    )

    /// UUIDs in the order they appear in `text`. Textual order is used rather than
    /// tree order because it is stable: the model is encoded with `.sortedKeys`, so
    /// the same model always produces the same string.
    static func uuids(in text: String) -> [String] {
        guard let regex = uuidPattern else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            Range(match.range, in: text).map { String(text[$0]).uppercased() }
        }
    }

    /// Three rungs are not pure functions of their input: v1 and v2 mint a default
    /// `CuePointType` (and v1 a `MediaItem`), and the v8–v10 tempo migration mints a
    /// synthetic "Tempo" cue per unmatched section. Their ids change on every run,
    /// so they cannot be pinned literally.
    ///
    /// Rather than skip those rungs — which are the ones most likely to diverge —
    /// every UUID in the output that did **not** appear in the input is replaced
    /// with `MINTED-0001`, `MINTED-0002`, … in order of first appearance. That keeps
    /// the rung fully pinned in shape, count and placement, while letting the values
    /// themselves vary. Carried-through ids stay literal, so a rung that *loses* an
    /// id still fails.
    static func normalisingMintedIdentifiers(
        output: String, input: String
    ) -> (text: String, mintedCount: Int) {
        let carried = Set(uuids(in: input))
        var assignments: [String: String] = [:]
        var order: [String] = []

        for uuid in uuids(in: output) where !carried.contains(uuid) && assignments[uuid] == nil {
            order.append(uuid)
            assignments[uuid] = String(format: "MINTED-%04d", order.count)
        }

        var text = output
        for (uuid, placeholder) in assignments {
            // Replace both cases: Swift encodes UUIDs uppercased, but a fixture may
            // have carried a lowercased one through.
            text = text.replacingOccurrences(of: uuid, with: placeholder)
            text = text.replacingOccurrences(of: uuid.lowercased(), with: placeholder)
        }
        return (text, order.count)
    }

    /// Migrate one legacy document and canonicalise the result.
    static func expectation(for json: String) throws -> CanonicalJSON {
        let migrated = try ProjectModel.decode(from: Data(json.utf8))

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let encoded = try encoder.encode(migrated)
        let text = try XCTUnwrap(String(data: encoded, encoding: .utf8))

        let normalised = normalisingMintedIdentifiers(output: text, input: json).text
        let tree = try JSONDecoder().decode(CanonicalJSON.self, from: Data(normalised.utf8))
        return tree.sortingStringArray(forKey: "includedTypeIDs")
    }

    static func make() throws -> CuelistMigrationGoldenVector {
        CuelistMigrationGoldenVector(
            contract: "cuelist-migration",
            version: 1,
            note: "macOS-generated golden vectors for the OnlyCue schema ladder. One "
                + "representative document per schema version 1...23, each paired with "
                + "the v23 model the Swift ladder produces. The C# OnlyCue.Core "
                + "re-implementation must reproduce every case. UUIDs that the "
                + "migration mints (v1, v2, and the v8-v10 tempo fan-out) appear as "
                + "MINTED-000N placeholders, numbered by first appearance, because "
                + "their real values differ on every run; ids carried over from the "
                + "input stay literal. includedTypeIDs is sorted because it is a "
                + "Swift Set and its JSON order is randomised per process. To "
                + "regenerate after a deliberate ladder change, delete "
                + "golden/cuelist-migration-v1.json and re-run the test suite.",
            cases: try CuelistMigrationFixture.all.map { fixture in
                CuelistMigrationGoldenVector.Case(
                    name: "v\(fixture.version)",
                    schemaVersion: fixture.version,
                    inputJSON: fixture.json,
                    expect: try expectation(for: fixture.json)
                )
            }
        )
    }

    /// Deterministic encoding so the committed file is stable and diff-friendly.
    static func encoded(_ vector: CuelistMigrationGoldenVector) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(vector)
    }
}

// MARK: - Tests

final class CuelistMigrationGoldenVectorTests: XCTestCase {

    private func goldenURL() throws -> URL {
        try repoRoot().appendingPathComponent("golden", isDirectory: true)
            .appendingPathComponent("cuelist-migration-v1.json")
    }

    /// Every rung must be represented. A gap here is how a version quietly stops
    /// being covered as the schema grows.
    func test_fixtures_coverEverySchemaVersion() {
        let versions = CuelistMigrationFixture.all.map(\.version)
        XCTAssertEqual(versions, Array(1...ProjectModel.currentSchemaVersion))
    }

    /// Each fixture must actually declare the version it claims, or the vector
    /// would silently exercise the wrong rung.
    func test_eachFixture_declaresItsOwnSchemaVersion() throws {
        for fixture in CuelistMigrationFixture.all {
            let probe = try JSONDecoder().decode(
                SchemaProbe.self, from: Data(fixture.json.utf8)
            )
            XCTAssertEqual(
                probe.schemaVersion,
                fixture.version,
                "fixture v\(fixture.version) declares schemaVersion \(probe.schemaVersion)"
            )
        }
    }

    /// Independent of the generator, so a broken ladder fails here rather than
    /// silently baking wrong "golden" values.
    func test_everyFixture_migratesToCurrentSchema() throws {
        for fixture in CuelistMigrationFixture.all {
            let migrated = try ProjectModel.decode(from: Data(fixture.json.utf8))
            XCTAssertEqual(
                migrated.schemaVersion,
                ProjectModel.currentSchemaVersion,
                "v\(fixture.version) did not land on the current schema"
            )
        }
    }

    /// The normalisation is only trustworthy if it leaves carried-through ids
    /// alone. v22 mints nothing, so its output must contain no placeholder.
    func test_normalisation_leavesCarriedIdentifiersLiteral() throws {
        let expect = try CuelistMigrationGolden.expectation(for: CuelistMigrationFixture.v22)
        let strings = expect.allStrings

        XCTAssertFalse(
            strings.contains { $0.hasPrefix("MINTED-") },
            "v22 is a purely additive rung and must mint nothing"
        )
        XCTAssertTrue(strings.contains("22220000-2222-0000-2222-000022220000".uppercased()))
    }

    /// The rungs that *do* mint must show placeholders — otherwise the normalisation
    /// silently did nothing and the test above would pass for the wrong reason.
    func test_normalisation_replacesMintedIdentifiers() throws {
        let expect = try CuelistMigrationGolden.expectation(for: CuelistMigrationFixture.v1)
        XCTAssertTrue(
            expect.allStrings.contains { $0.hasPrefix("MINTED-") },
            "v1 mints a cue point type and a media item id"
        )
    }

    /// Two runs of the same rung must canonicalise identically, or the drift guard
    /// would fail at random. This is the property the `Set` sort exists for.
    func test_canonicalisation_isStableAcrossRuns() throws {
        for fixture in [CuelistMigrationFixture.v17, CuelistMigrationFixture.v1] {
            let first = try CuelistMigrationGolden.expectation(for: fixture)
            let second = try CuelistMigrationGolden.expectation(for: fixture)
            XCTAssertEqual(first, second)
        }
    }

    /// Bootstrap-and-fail on first run, byte-compare afterwards. Deleting the file
    /// regenerates it and fails, so a deliberate ladder change still gets reviewed.
    func test_committedVectors_matchCurrentSwiftOutput() throws {
        let url = try goldenURL()
        let data = try CuelistMigrationGolden.encoded(CuelistMigrationGolden.make())

        guard FileManager.default.fileExists(atPath: url.path) else {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try data.write(to: url)
            XCTFail("wrote \(url.lastPathComponent); re-run to verify and commit it")
            return
        }

        let committed = try Data(contentsOf: url)
        XCTAssertEqual(
            committed,
            data,
            "golden/cuelist-migration-v1.json is stale — the migration ladder changed. "
                + "Delete the file and re-run to regenerate, then review the diff."
        )
    }

    private struct SchemaProbe: Decodable {
        let schemaVersion: Int
    }
}
