import XCTest
@testable import OnlyCue

final class CuelistCryptoTests: XCTestCase {

    func test_seal_then_open_roundTrips() throws {
        let payload = Data(#"{"schemaVersion":12,"name":"Show"}"#.utf8)
        let sealed = try CuelistCrypto.seal(payload)
        XCTAssertEqual(sealed.prefix(4), Data("OCUE".utf8), "sealed output must start with the OCUE magic")
        XCTAssertNotEqual(sealed, payload, "sealed output must not be the plaintext")
        XCTAssertEqual(try CuelistCrypto.open(sealed), payload)
    }

    func test_seal_emptyAndLarge_roundTrip() throws {
        for payload in [Data(), Data(repeating: 0xAB, count: 200_000)] {
            XCTAssertEqual(try CuelistCrypto.open(CuelistCrypto.seal(payload)), payload)
        }
    }

    func test_open_legacyPlaintext_passesThroughUnchanged() throws {
        let legacy = Data(#"{"schemaVersion":12,"name":"Legacy"}"#.utf8)
        XCTAssertEqual(try CuelistCrypto.open(legacy), legacy, "no OCUE magic ⇒ return bytes unchanged")
    }

    func test_open_tamperedTagOrCiphertext_throwsCryptoErrorNotCryptoKitError() throws {
        // The seam must own its error domain: a failed auth tag (tampered file)
        // must surface as CuelistCrypto.CryptoError, not a leaked CryptoKitError,
        // so CueListDocument can map every crypto failure to a corrupt-file error.
        let plaintext = Data("hello world payload to make a ciphertext".utf8)

        var tamperedTag = try CuelistCrypto.seal(plaintext)
        tamperedTag[tamperedTag.count - 1] ^= 0xFF // flip a tag byte
        XCTAssertThrowsError(try CuelistCrypto.open(tamperedTag)) { error in
            XCTAssertEqual(error as? CuelistCrypto.CryptoError, .decryptionFailed)
        }

        var tamperedCipher = try CuelistCrypto.seal(plaintext)
        tamperedCipher[20] ^= 0xFF // flip a ciphertext byte (past the 17-byte header)
        XCTAssertThrowsError(try CuelistCrypto.open(tamperedCipher)) { error in
            XCTAssertEqual(error as? CuelistCrypto.CryptoError, .decryptionFailed)
        }
    }

    func test_open_truncatedEnvelope_throws() {
        let tooShort = Data("OCUE".utf8) + Data([0x01, 0x00])
        XCTAssertThrowsError(try CuelistCrypto.open(tooShort))
    }

    func test_open_unknownVersion_throws() {
        var bad = Data("OCUE".utf8)
        bad.append(0x99)
        bad.append(Data(repeating: 0, count: 30))
        XCTAssertThrowsError(try CuelistCrypto.open(bad))
    }
}
