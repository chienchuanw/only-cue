import XCTest

/// #833 — what `GoldenDouble`'s transport can and cannot carry.
///
/// The golden vectors compare doubles **bitwise**, so the text in the file has
/// to determine the bit pattern exactly. A mnemonic cannot: Swift's `"nan"`
/// means `0x7FF8000000000000` and .NET parses the same four characters back to
/// `0xFFF8000000000000` (its `double.NaN` carries the sign bit). Both were
/// measured, not assumed. So NaN travels as its bits, and every spelling only
/// one platform accepts is refused by both.
final class GoldenDoubleTests: XCTestCase {

    // MARK: - NaN carries its bits

    func test_theCanonicalNaN_travelsAsItsBitPattern() throws {
        XCTAssertEqual(try encode(.nan), "nan:0x7FF8000000000000")
    }

    /// The acceptance case from #833: a NaN that came out of an algorithm rather
    /// than from the `Double.nan` constant. Widening any binary32 NaN yields
    /// `0x7FF8…`, which is precisely the pattern .NET cannot name.
    func test_aWidenedBinary32NaN_spellsTheSameAsTheCanonicalNaN() throws {
        let widened = Double(Float(bitPattern: 0x7FC0_0000))
        XCTAssertEqual(try encode(widened), "nan:0x7FF8000000000000")
    }

    func test_theSignBitSurvives() throws {
        XCTAssertEqual(try encode(-Double.nan), "nan:0xFFF8000000000000")
        XCTAssertNotEqual(try decode("nan:0x7FF8000000000000"),
                          try decode("nan:0xFFF8000000000000"))
    }

    func test_aNaNPayloadSurvives() throws {
        let payload = Double(bitPattern: 0x7FF8_0000_0000_0001)
        XCTAssertEqual(try encode(payload), "nan:0x7FF8000000000001")
        XCTAssertEqual(try decode("nan:0x7FF8000000000001").bitPattern, payload.bitPattern)
    }

    // MARK: - Spellings only one platform accepts

    /// The mnemonics are refused rather than reinterpreted. Accepting them would
    /// mean picking a sign for the reader, and the two platforms pick different
    /// ones — which is the whole defect.
    func test_bareNaNMnemonics_areRejected() {
        for text in ["nan", "-nan", "NaN"] {
            XCTAssertThrowsError(try decode(text), "\(text) must not decode")
        }
    }

    /// `Double("0x7FF8000000000000")` is **9.221120237041091e+18** on Swift — a
    /// plausible finite number, silently — while .NET's `TryParse` refuses it.
    /// Both measured. A bare-hex spelling would therefore have been the worst
    /// possible carrier for a bit pattern: wrong on one side without failing,
    /// which is why the marker prefix exists.
    func test_hexFloatSpellings_areRejected() {
        for text in ["0x7FF8000000000000", "0x1p3", "-0x1p3", "0x1F"] {
            XCTAssertThrowsError(try decode(text), "\(text) must not decode")
        }
    }

    func test_aMalformedBitPattern_isRejected() {
        for text in ["nan:0x", "nan:0xZZZ8000000000000", "nan:7FF8000000000000",
                     "nan:0x7FF80000000000000"] {
            XCTAssertThrowsError(try decode(text), "\(text) must not decode")
        }
    }

    // MARK: - Everything else is unchanged

    /// The infinities have exactly one bit pattern each, so their mnemonics are
    /// lossless and stay. This pins that the NaN change did not disturb them.
    func test_finiteValuesAndInfinities_keepTheirSpelling() throws {
        for (value, text) in [(1.0, "1.0"), (-0.0, "-0.0"), (1e-05, "1e-05"),
                              (Double.infinity, "inf"), (-Double.infinity, "-inf")] {
            XCTAssertEqual(try encode(value), text)
        }
        for (text, value) in [("1.0", 1.0), ("-0.0", -0.0), ("1e-05", 1e-05),
                              ("inf", Double.infinity), ("-inf", -Double.infinity)] {
            XCTAssertEqual(try decode(text).bitPattern, value.bitPattern, text)
        }
    }

    // MARK: - Harness

    /// Encoded inside an array because the vectors never carry a bare fragment,
    /// and the quotes are stripped so the assertions read as the file's text.
    private func encode(_ value: Double) throws -> String {
        let data = try JSONEncoder().encode([GoldenDouble(value)])
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        return String(text.dropFirst(2).dropLast(2))
    }

    private func decode(_ text: String) throws -> Double {
        let data = try XCTUnwrap("[\"\(text)\"]".data(using: .utf8))
        return try JSONDecoder().decode([GoldenDouble].self, from: data)[0].value
    }
}
