import XCTest
@testable import OnlyCue

@MainActor
final class CueListDocumentTests: XCTestCase {

    func test_initEmpty_seedsDefaultCuePointType() {
        let document = CueListDocument()

        XCTAssertEqual(document.model.cuePointTypes.count, 1, "new documents must seed exactly one default Type")
        let defaultType = document.model.cuePointTypes.first
        XCTAssertEqual(defaultType?.name, "General")
        XCTAssertEqual(defaultType?.colorHex, "#4ECDC4")
    }

    func test_encodeModel_producesEncryptedEnvelope() throws {
        let model = CueListDocument().model
        let data = try CueListDocument.encodeModel(model)
        XCTAssertEqual(data.prefix(4), Data("OCUE".utf8), "saved files must be sealed")
    }

    func test_encodeThenDecode_roundTripsModel() throws {
        let original = CueListDocument().model
        let decoded = try CueListDocument.decodeModel(from: CueListDocument.encodeModel(original))
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.cuePointTypes.map(\.name), original.cuePointTypes.map(\.name))
        XCTAssertEqual(decoded.schemaVersion, original.schemaVersion)
    }

    func test_decodeModel_readsLegacyPlaintext() throws {
        let original = CueListDocument().model
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let legacyPlaintext = try encoder.encode(original) // no OCUE envelope
        let decoded = try CueListDocument.decodeModel(from: legacyPlaintext)
        XCTAssertEqual(decoded.id, original.id, "pre-encryption .cuelist files must still open")
    }

    func test_decodeModel_tamperedEnvelope_throwsCryptoError() throws {
        // Issue #304 AC: a tampered file must surface as a corrupt-file error.
        // init(configuration:) maps CuelistCrypto.CryptoError → CocoaError(.fileReadCorruptFile);
        // this asserts the seam delivers that error domain (not a leaked CryptoKitError)
        // for a failed auth tag, which is the contract init relies on.
        var sealed = try CueListDocument.encodeModel(CueListDocument().model)
        sealed[sealed.count - 1] ^= 0xFF
        XCTAssertThrowsError(try CueListDocument.decodeModel(from: sealed)) { error in
            XCTAssertTrue(error is CuelistCrypto.CryptoError, "got \(type(of: error)): \(error)")
        }
    }
}
