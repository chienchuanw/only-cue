import XCTest
@testable import OnlyCue

@MainActor
final class CueListDocumentTests: XCTestCase {

    func test_initEmpty_seedsCanonicalCuePointTypes() {
        let document = CueListDocument()

        // Audit §2.2: new documents seed the 5 canonical cue types
        // (General, Lighting, Sound, Scene, Standby) so the Figma export-sheet
        // reference renders out of the box. Order is canonical — General leads
        // so the existing `defaultCuePointTypeID` accessor (first element)
        // continues to resolve to "General".
        XCTAssertEqual(
            document.model.cuePointTypes.map(\.name),
            ["General", "Lighting", "Sound", "Scene", "Standby"]
        )
        XCTAssertEqual(document.model.cuePointTypes.first?.colorHex, "#4ECDC4")
        XCTAssertEqual(Set(document.model.cuePointTypes.map(\.colorHex)).count, 5, "every default type uses a distinct palette color")
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
