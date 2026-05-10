import XCTest
@testable import OnlyCue

/// Pins the per-Type filter behavior. Empty allow-set is "no filter" — the
/// natural UI default. Filter preserves input order so downstream exporters
/// don't observe a re-sort they didn't request.
final class CueExportFilterTests: XCTestCase {

    func test_emptyAllowSet_returnsAllCues() {
        let cues = [makeCue(typeID: UUID()), makeCue(typeID: UUID())]
        let filtered = CueExportFilter.cues(cues, onlyTypeIDs: [])
        XCTAssertEqual(filtered.count, 2)
    }

    func test_excludesCuesWithDisallowedTypeID() {
        let lighting = UUID()
        let sound = UUID()
        let cues = [
            makeCue(typeID: lighting, name: "L1"),
            makeCue(typeID: sound, name: "S1"),
            makeCue(typeID: lighting, name: "L2")
        ]
        let filtered = CueExportFilter.cues(cues, onlyTypeIDs: [lighting])
        XCTAssertEqual(filtered.map(\.name), ["L1", "L2"])
    }

    func test_unionOfMultipleAllowedTypes() {
        let lighting = UUID()
        let sound = UUID()
        let video = UUID()
        let cues = [
            makeCue(typeID: lighting, name: "L"),
            makeCue(typeID: sound, name: "S"),
            makeCue(typeID: video, name: "V")
        ]
        let filtered = CueExportFilter.cues(cues, onlyTypeIDs: [lighting, video])
        XCTAssertEqual(filtered.map(\.name), ["L", "V"])
    }

    func test_preservesInputOrder() {
        // If callers fed a deliberately-unsorted list (e.g. a UI-driven order),
        // the filter must not silently re-sort. `.filter` semantics already
        // give us this; the test pins it as part of the contract.
        let typeID = UUID()
        let cues = [
            makeCue(typeID: typeID, name: "third"),
            makeCue(typeID: typeID, name: "first"),
            makeCue(typeID: typeID, name: "second")
        ]
        let filtered = CueExportFilter.cues(cues, onlyTypeIDs: [typeID])
        XCTAssertEqual(filtered.map(\.name), ["third", "first", "second"])
    }

    private func makeCue(typeID: UUID, name: String = "x") -> Cue {
        Cue(
            id: UUID(),
            typeID: typeID,
            cueNumber: 1,
            name: name,
            time: 0,
            notes: "",
            fadeTime: .zero
        )
    }
}
