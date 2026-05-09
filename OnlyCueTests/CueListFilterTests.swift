import XCTest
@testable import OnlyCue

final class CueListFilterTests: XCTestCase {

    func test_emptyQuery_returnsAllCues() {
        let cues = [makeCue(name: "A"), makeCue(name: "B")]
        XCTAssertEqual(CueListPane.filtered(cues, by: "").count, 2)
    }

    func test_whitespaceQuery_returnsAllCues() {
        let cues = [makeCue(name: "A"), makeCue(name: "B")]
        XCTAssertEqual(CueListPane.filtered(cues, by: "   ").count, 2)
    }

    func test_nameMatch_returnsOnlyMatching() {
        let cues = [
            makeCue(name: "GO Wash"),
            makeCue(name: "Crossfade"),
            makeCue(name: "Wash on Bart")
        ]
        let result = CueListPane.filtered(cues, by: "wash")
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(Set(result.map(\.name)), Set(["GO Wash", "Wash on Bart"]))
    }

    func test_notesMatch_returnsOnlyMatching() {
        let cues = [
            makeCue(name: "A", notes: "GO on the downbeat"),
            makeCue(name: "B", notes: "fade slowly"),
            makeCue(name: "C", notes: "")
        ]
        let result = CueListPane.filtered(cues, by: "downbeat")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.name, "A")
    }

    func test_caseInsensitive_matchesRegardlessOfCase() {
        let cues = [makeCue(name: "GO WASH"), makeCue(name: "crossfade")]
        XCTAssertEqual(CueListPane.filtered(cues, by: "wash").count, 1)
        XCTAssertEqual(CueListPane.filtered(cues, by: "CROSS").count, 1)
    }

    func test_noMatch_returnsEmpty() {
        let cues = [makeCue(name: "A"), makeCue(name: "B")]
        XCTAssertEqual(CueListPane.filtered(cues, by: "zzz").count, 0)
    }

    func test_matchesEitherNameOrNotes() {
        let cues = [
            makeCue(name: "Go Wash", notes: "act 1"),
            makeCue(name: "Crossfade", notes: "wash transition")
        ]
        let result = CueListPane.filtered(cues, by: "wash")
        XCTAssertEqual(result.count, 2)
    }

    private func makeCue(name: String, notes: String = "") -> Cue {
        Cue(
            id: UUID(),
            typeID: UUID(),
            cueNumber: 1,
            name: name,
            time: 0,
            notes: notes,
            fadeTime: .zero
        )
    }
}
