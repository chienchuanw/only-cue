import XCTest
@testable import OnlyCue

final class CueTempoFieldsTests: XCTestCase {

    func testCueHasOptionalBPMAndBeatsPerBarDefaultingToNil() {
        let cue = Cue(
            id: UUID(),
            typeID: UUID(),
            cueNumber: nil,
            name: "x",
            time: 1.0,
            notes: "",
            fadeTime: .zero
        )
        XCTAssertNil(cue.bpm)
        XCTAssertNil(cue.beatsPerBar)
    }

    func testCueEncodesAndDecodesTempoFields() throws {
        let cue = Cue(
            id: UUID(),
            typeID: UUID(),
            cueNumber: nil,
            name: "x",
            time: 1.0,
            notes: "",
            fadeTime: .zero,
            bpm: 120,
            beatsPerBar: 4
        )
        let data = try JSONEncoder().encode(cue)
        let decoded = try JSONDecoder().decode(Cue.self, from: data)
        XCTAssertEqual(decoded.bpm, 120)
        XCTAssertEqual(decoded.beatsPerBar, 4)
    }

    func testCueClampsBPMOnConstruction() {
        let low = Cue(
            id: UUID(), typeID: UUID(), cueNumber: nil,
            name: "", time: 0, notes: "", fadeTime: .zero,
            bpm: 5
        )
        let high = Cue(
            id: UUID(), typeID: UUID(), cueNumber: nil,
            name: "", time: 0, notes: "", fadeTime: .zero,
            bpm: 9999
        )
        XCTAssertEqual(low.bpm, 20)
        XCTAssertEqual(high.bpm, 400)
    }

    func testCueClampsBeatsPerBarOnConstruction() {
        let low = Cue(
            id: UUID(), typeID: UUID(), cueNumber: nil,
            name: "", time: 0, notes: "", fadeTime: .zero,
            beatsPerBar: 0
        )
        let high = Cue(
            id: UUID(), typeID: UUID(), cueNumber: nil,
            name: "", time: 0, notes: "", fadeTime: .zero,
            beatsPerBar: 99
        )
        XCTAssertEqual(low.beatsPerBar, 1)
        XCTAssertEqual(high.beatsPerBar, 16)
    }
}
