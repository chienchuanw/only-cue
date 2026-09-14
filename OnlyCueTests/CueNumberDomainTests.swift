import XCTest
@testable import OnlyCue

/// #830: a `cueNumber` outside grandMA2's `0.001...9999.999` domain reaches the
/// MA2 generators, where a negative one spells the malformed token `-1.-5` and a
/// large one traps the `Int((value * 1000).rounded())` conversion outright.
///
/// The document is the untrusted boundary — a `.cuelist` is hand-editable and
/// older builds never gated the number — so an out-of-domain value is coerced to
/// `nil` on decode: the cue opens as *unnumbered* rather than carrying a number
/// that means nothing. That follows the precedent `Cue.init` already sets for a
/// non-finite `bpm`, and unlike clamping it never invents a number the designer
/// did not choose.
///
/// Deliberately *not* mirrored in the memberwise initialiser: in-process
/// construction is trusted, and the MA2 golden vectors seat out-of-domain
/// numbers on purpose to pin cross-platform generator parity.
final class CueNumberDomainTests: XCTestCase {

    private func decodeCue(cueNumber: String) throws -> Cue {
        let json = """
        {
          "id": "\(UUID().uuidString)",
          "typeID": "\(UUID().uuidString)",
          "cueNumber": \(cueNumber),
          "name": "x",
          "time": 1,
          "notes": "",
          "fadeTime": {"fadeIn": 0, "fadeOut": 0}
        }
        """
        return try JSONDecoder().decode(Cue.self, from: Data(json.utf8))
    }

    // MARK: - decode coercion

    func test_decode_keepsInDomainNumbers() throws {
        XCTAssertEqual(try decodeCue(cueNumber: "1.5").cueNumber, 1.5)
        XCTAssertEqual(try decodeCue(cueNumber: "0.001").cueNumber, CueNumberValidator.minimum)
        XCTAssertEqual(try decodeCue(cueNumber: "9999.999").cueNumber, CueNumberValidator.maximum)
    }

    func test_decode_coercesNegativeToUnnumbered() throws {
        XCTAssertNil(try decodeCue(cueNumber: "-1.5").cueNumber)
    }

    func test_decode_coercesBelowMinimumToUnnumbered() throws {
        // Zero is below the minimum: MA2 numbering starts at 0.001.
        XCTAssertNil(try decodeCue(cueNumber: "0").cueNumber)
        XCTAssertNil(try decodeCue(cueNumber: "0.0005").cueNumber)
    }

    func test_decode_coercesAboveMaximumToUnnumbered() throws {
        XCTAssertNil(try decodeCue(cueNumber: "10000").cueNumber)
        // 3e6 × 1000 overflows Int32; 1e16 × 1000 traps Swift's own `Int`.
        XCTAssertNil(try decodeCue(cueNumber: "3000000").cueNumber)
        XCTAssertNil(try decodeCue(cueNumber: "1e16").cueNumber)
    }

    func test_decode_keepsAbsentNumberUnnumbered() throws {
        let json = """
        {
          "id": "\(UUID().uuidString)",
          "typeID": "\(UUID().uuidString)",
          "name": "x",
          "time": 1,
          "notes": "",
          "fadeTime": {"fadeIn": 0, "fadeOut": 0}
        }
        """
        XCTAssertNil(try JSONDecoder().decode(Cue.self, from: Data(json.utf8)).cueNumber)
    }

    // A fourth decimal place is *not* out of domain — the generators round it
    // into thousandths harmlessly, so nil-ing it would be gratuitous data loss.
    // Only the range (and finiteness) gates the decode.
    func test_decode_keepsAFourthDecimalPlace() throws {
        XCTAssertEqual(try decodeCue(cueNumber: "1.0005").cueNumber, 1.0005)
    }

    // MARK: - memberwise construction stays unchecked

    func test_memberwiseInit_keepsOutOfDomainNumbers() {
        let cue = Cue(
            id: UUID(), typeID: UUID(), cueNumber: -1.5,
            name: "x", time: 0, notes: "", fadeTime: .zero
        )
        XCTAssertEqual(cue.cueNumber, -1.5)
    }
}
