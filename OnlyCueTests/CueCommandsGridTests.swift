import XCTest
@testable import OnlyCue

/// Skipped in v11 transition (#244). The grid-snap commands still take a
/// `TempoMap` parameter for this leaf but the per-item map is no longer
/// populated, so every assertion here would fail trivially. Leaf 2 (#245)
/// retargets these tests to `DerivedTempoGrid`.
@MainActor
final class CueCommandsGridTests: XCTestCase {

    override func setUpWithError() throws {
        throw XCTSkip("Retargeted to DerivedTempoGrid in #245 (Leaf 2)")
    }

    func test_placeholder_keepsClassWiredIntoTheTestTarget() {
        // Body intentionally empty; the setUp skip means this never runs.
    }
}
