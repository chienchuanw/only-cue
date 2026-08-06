import XCTest

/// Q8 conformance gate: every main-window view must consume `DS.*` tokens, not
/// raw color / spacing / font literals. A line opts out of the scan only with
/// a trailing `// semantic:` or `// off-grid:` annotation (documented
/// exceptions — e.g. a semantic error color, an SF Symbol glyph size).
final class TokenConformanceTests: XCTestCase {

    /// The main-window view set scanned by the gate. ADR-024.
    private let mainWindowFiles = [
        "DocumentView.swift", "DocumentView+Bindings.swift",
        "DocumentView+ManageTypes.swift", "DocumentView+PauseAtEachCue.swift",
        "DocumentEmptyState.swift", "PreviewPane.swift", "ItemListPane.swift",
        "ItemRowView.swift", "EditorModeSwitcher.swift", "LTCStrip.swift",
        "ModeAwareInspector.swift", "CueListPane.swift", "CueListPane+Sheets.swift",
        "CueRowView.swift", "CueColorSwatch.swift", "TransportControls.swift",
        "ShortcutReferencePopover.swift"
    ]

    /// Patterns that indicate a raw literal where a `DS.*` token belongs.
    private let banned: [(name: String, regex: String)] = [
        ("raw Color literal", #"Color\.(white|black|gray|red|green|blue|orange|yellow|purple|pink|accentColor)\b"#),
        ("system font size", #"\.font\(\.system\(size:"#),
        ("magic padding", #"\.padding\([^)]*\b[1-9][0-9]*\b[^)]*\)"#)
    ]

    /// `OnlyCue/UI`, resolved via the shared `repoRoot()` test helper (walks up
    /// to the `project.yml` marker).
    private func uiDirectory() throws -> URL {
        try repoRoot().appendingPathComponent("OnlyCue/UI")
    }

    func testMainWindowViewsUseTokensNotLiterals() throws {
        var violations: [String] = []
        let uiDirectory = try uiDirectory()
        for file in mainWindowFiles {
            let url = uiDirectory.appendingPathComponent(file)
            guard let source = try? String(contentsOf: url, encoding: .utf8) else {
                XCTFail("missing main-window file: \(file)")
                continue
            }
            for (index, line) in source.components(separatedBy: .newlines).enumerated() {
                if line.contains("// semantic:") || line.contains("// off-grid:") { continue }
                if line.contains("DS.") { continue }
                for rule in banned where line.range(of: rule.regex, options: .regularExpression) != nil {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    violations.append("\(file):\(index + 1) — \(rule.name): \(trimmed)")
                }
            }
        }
        XCTAssertTrue(
            violations.isEmpty,
            "Token conformance failures:\n" + violations.joined(separator: "\n")
        )
    }
}
