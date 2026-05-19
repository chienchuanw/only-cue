import Foundation
import CryptoKit

/// Seals/opens the on-disk `.cuelist` envelope. The plaintext inside is exactly
/// the pretty-printed sorted-keys JSON of `ProjectModel`, so the schema/migration
/// machinery never sees ciphertext. AES-256-GCM gives confidentiality vs. casual
/// snooping plus an authentication tag (tamper-evidence). The key is compiled
/// into the binary and is extractable by reverse-engineering — acceptable under
/// the threat model recorded in ADR-021.
enum CuelistCrypto {

    enum CryptoError: Error { case malformedEnvelope, unsupportedVersion, decryptionFailed }

    private static let magic = Data("OCUE".utf8) // ASCII "OCUE"
    private static let version: UInt8 = 0x01
    private static let nonceLength = 12          // AES-GCM nonce
    private static let tagLength = 16            // AES-GCM auth tag
    private static var versionOffset: Int { magic.count }
    private static var nonceOffset: Int { magic.count + 1 }
    private static var headerLength: Int { magic.count + 1 + nonceLength }

    /// 32-byte fixed app key. Intentionally extractable (see ADR-021).
    private static let key = SymmetricKey(data: Data([
        0x4F, 0x6E, 0x6C, 0x79, 0x43, 0x75, 0x65, 0x2D,
        0x76, 0x31, 0x2D, 0x64, 0x6F, 0x63, 0x75, 0x6D,
        0x65, 0x6E, 0x74, 0x2D, 0x6B, 0x65, 0x79, 0x2D,
        0x41, 0x45, 0x53, 0x32, 0x35, 0x36, 0x47, 0x43
    ]))

    static func seal(_ json: Data) throws -> Data {
        let sealed = try AES.GCM.seal(json, using: key)
        var out = Data()
        out.append(magic)
        out.append(version)
        out.append(sealed.nonce.withUnsafeBytes { Data($0) })
        out.append(sealed.ciphertext)
        out.append(sealed.tag)
        return out
    }

    static func open(_ fileData: Data) throws -> Data {
        let file = Data(fileData) // normalize to 0-based indices
        guard file.count >= magic.count, file.prefix(magic.count) == magic else {
            return fileData // legacy plaintext: return bytes unchanged
        }
        guard file.count >= headerLength + tagLength else { throw CryptoError.malformedEnvelope }
        guard file[versionOffset] == version else { throw CryptoError.unsupportedVersion }
        let nonceData = file.subdata(in: nonceOffset ..< nonceOffset + nonceLength)
        let rest = file.subdata(in: headerLength ..< file.count)
        let ciphertext = rest.prefix(rest.count - tagLength)
        let tag = rest.suffix(tagLength)
        do {
            let box = try AES.GCM.SealedBox(
                nonce: AES.GCM.Nonce(data: nonceData),
                ciphertext: ciphertext,
                tag: tag
            )
            return try AES.GCM.open(box, using: key)
        } catch {
            // Wrap CryptoKit failures (failed auth tag on a tampered file, bad
            // nonce) into this seam's own error domain so callers map every
            // crypto failure to a corrupt-file error in one place.
            throw CryptoError.decryptionFailed
        }
    }
}
