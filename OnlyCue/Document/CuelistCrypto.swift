import Foundation
import CryptoKit

/// Seals/opens the on-disk `.cuelist` envelope. The plaintext inside is exactly
/// the pretty-printed sorted-keys JSON of `ProjectModel`, so the schema/migration
/// machinery never sees ciphertext. AES-256-GCM gives confidentiality vs. casual
/// snooping plus an authentication tag (tamper-evidence). The key is compiled
/// into the binary and is extractable by reverse-engineering — acceptable under
/// the threat model recorded in ADR-021.
enum CuelistCrypto {

    enum CryptoError: Error { case malformedEnvelope, unsupportedVersion }

    private static let magic = Data("OCUE".utf8) // 4 bytes
    private static let version: UInt8 = 0x01
    private static let headerLength = 17         // 4 magic + 1 version + 12 nonce

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
        guard file.count > headerLength else { throw CryptoError.malformedEnvelope }
        guard file[magic.count] == version else { throw CryptoError.unsupportedVersion }
        let nonceData = file.subdata(in: 5 ..< 17)
        let rest = file.subdata(in: 17 ..< file.count)
        guard rest.count >= 16 else { throw CryptoError.malformedEnvelope }
        let ciphertext = rest.prefix(rest.count - 16)
        let tag = rest.suffix(16)
        let box = try AES.GCM.SealedBox(
            nonce: AES.GCM.Nonce(data: nonceData),
            ciphertext: ciphertext,
            tag: tag
        )
        return try AES.GCM.open(box, using: key)
    }
}
