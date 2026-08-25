import XCTest

/// Source-level guard for #770: app code must not reach for
/// `NSApp.orderedWindows`.
///
/// `orderedWindows` silently omits every `NSPanel`, so using it to locate a
/// panel compiles, type-checks, passes review and then reports `false` forever
/// — which is exactly how the Mini Player keyboard gate shipped dead through
/// three releases. `NSApp.windows` includes panels and is what this codebase
/// already uses elsewhere (`DocumentView+Workspace.swift`).
///
/// A line opts out with a trailing `// orderedWindows-ok:` annotation stating
/// why panels are irrelevant there.
final class OrderedWindowsBanTests: XCTestCase {

    func testAppSourceDoesNotUseOrderedWindows() throws {
        let sourceRoot = try repoRoot().appendingPathComponent("OnlyCue")
        let files = FileManager.default
            .enumerator(at: sourceRoot, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" } ?? []
        XCTAssertFalse(files.isEmpty, "no Swift sources found under \(sourceRoot.path)")

        var violations: [String] = []
        for url in files {
            guard let source = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for (index, line) in source.components(separatedBy: .newlines).enumerated() {
                guard line.contains("orderedWindows") else { continue }
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("//") { continue }  // prose about the ban itself
                if line.contains("// orderedWindows-ok:") { continue }
                violations.append("\(url.lastPathComponent):\(index + 1) — \(trimmed)")
            }
        }
        XCTAssertTrue(
            violations.isEmpty,
            "NSApp.orderedWindows excludes NSPanel; use NSApp.windows instead:\n"
                + violations.joined(separator: "\n")
        )
    }
}
