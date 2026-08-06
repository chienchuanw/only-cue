import XCTest

/// The subset of the String Catalog JSON schema this gate reads.
private struct Catalog: Decodable {
    let sourceLanguage: String
    let strings: [String: Entry]
}

private struct Entry: Decodable {
    let extractionState: String?
}

/// Phase 1 (keys-exist mode) localization gate.
///
/// Guards the integrity of the String Catalog that every user-facing string is
/// routed through. It does **not** yet assert zh-Hant translations — Phase 2
/// flips `assertTranslated(into:)` on for `zh-Hant`. See
/// `docs/superpowers/specs/2026-08-06-zh-hant-localization-design.md`.
///
/// What it enforces today:
/// - the catalog exists, is valid JSON, and declares `en` as its source language;
/// - it holds a real harvest, not an empty/wiped file (a floor on entry count);
/// - a handful of representative strings are present (catches a regenerated-empty
///   or accidentally-cleared catalog);
/// - no entry is `stale` — i.e. a key no longer referenced in code that should be
///   pruned rather than shipped and (later) translated.
final class LocalizationCompletenessTests: XCTestCase {

    /// Minimum number of catalog entries. The app had 108 `Text("…")` literals
    /// before this work plus the non-`Text` strings routed through the catalog,
    /// so a healthy catalog is comfortably above this floor. Set low enough to
    /// avoid churn on every string added or removed, high enough to fail loudly
    /// if the catalog is wiped.
    private let minimumEntryCount = 100

    /// Strings that must always be in the catalog. Drawn from stable, visible UI
    /// (the launch screen, the MA2 push sheet, the empty preview state). If the
    /// catalog is regenerated empty or these views stop routing through it, the
    /// test names exactly what went missing.
    private let representativeKeys = [
        "OnlyCue",
        "Plan and run lighting cues against your media.",
        "Send to grandMA2",
        "Import audio or video to preview"
    ]

    // MARK: - Catalog location

    /// `OnlyCue/Resources/Localizable.xcstrings`, resolved from this test file's
    /// compile-time path by walking up to the `project.yml` marker — robust to
    /// the self-hosted CI runner's `_work/<repo>/<repo>/…` layout, mirroring
    /// `TokenConformanceTests`.
    private func catalogURL() throws -> URL {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let fileManager = FileManager.default
        while dir.path != "/" {
            if fileManager.fileExists(atPath: dir.appendingPathComponent("project.yml").path) {
                return dir
                    .appendingPathComponent("OnlyCue/Resources/Localizable.xcstrings")
            }
            dir.deleteLastPathComponent()
        }
        throw XCTSkip("could not locate project.yml from \(#filePath)")
    }

    private func loadCatalog() throws -> Catalog {
        let url = try catalogURL()
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Catalog.self, from: data)
    }

    // MARK: - Tests

    func testCatalogIsValidAndSourcedInEnglish() throws {
        let catalog = try loadCatalog()
        XCTAssertEqual(
            catalog.sourceLanguage,
            "en",
            "Localizable.xcstrings sourceLanguage must stay 'en' (developmentLanguage)."
        )
    }

    func testCatalogHoldsARealHarvest() throws {
        let catalog = try loadCatalog()
        XCTAssertGreaterThanOrEqual(
            catalog.strings.count,
            minimumEntryCount,
            """
            Localizable.xcstrings has \(catalog.strings.count) entries, below the \
            floor of \(minimumEntryCount). The catalog looks wiped or under-harvested \
            — build the app so Xcode extracts strings, or route more UI through it.
            """
        )
    }

    func testRepresentativeKeysArePresent() throws {
        let catalog = try loadCatalog()
        let missing = representativeKeys.filter { catalog.strings[$0] == nil }
        XCTAssertTrue(
            missing.isEmpty,
            "Localizable.xcstrings is missing expected keys:\n" + missing.joined(separator: "\n")
        )
    }

    func testNoStaleEntries() throws {
        let catalog = try loadCatalog()
        let stale = catalog.strings
            .filter { $0.value.extractionState == "stale" }
            .keys
            .sorted()
        XCTAssertTrue(
            stale.isEmpty,
            """
            Localizable.xcstrings has stale entries (keys no longer referenced in \
            code). Prune them from the catalog:
            """ + "\n" + stale.joined(separator: "\n")
        )
    }
}
