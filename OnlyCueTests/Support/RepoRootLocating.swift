import XCTest

extension XCTestCase {
    /// The repository root, resolved from the calling test file's compile-time
    /// path by walking up to the `project.yml` xcodegen marker.
    ///
    /// Robust to the self-hosted CI runner's `_work/<repo>/<repo>/…` layout,
    /// where a fixed "up N components" traversal breaks. The default
    /// `#filePath` argument is evaluated at the call site, so the walk starts
    /// from whichever test file calls this.
    func repoRoot(from filePath: String = #filePath) throws -> URL {
        var dir = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        let fileManager = FileManager.default
        while dir.path != "/" {
            if fileManager.fileExists(atPath: dir.appendingPathComponent("project.yml").path) {
                return dir
            }
            dir.deleteLastPathComponent()
        }
        throw XCTSkip("could not locate project.yml from \(filePath)")
    }
}
