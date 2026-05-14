import XCTest
@testable import OnlyCue

/// Skipped in v11 transition (#244). The section-based tempo commands
/// (`setTempoMap`, `addTempoSection`, etc.) are still in the source tree for
/// build continuity but are now no-ops (the per-item `tempoMap` is dropped).
/// They get deleted in Leaf 5 (#248); Leaf 3 (#246) adds `setCueTempo` with
/// fresh coverage.
@MainActor
final class CueCommandsTempoTests: XCTestCase {

    override func setUpWithError() throws {
        throw XCTSkip("Replaced by CueCommandsSetTempoTests in #246 (Leaf 3); section commands removed in #248 (Leaf 5)")
    }

    func test_placeholder_keepsClassWiredIntoTheTestTarget() {
        // Body intentionally empty.
    }
}
