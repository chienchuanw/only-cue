import Foundation
import CryptoKit

/// Seals/opens OnlyCue's encrypted envelopes. Two file types share the scheme:
/// the `.cuelist` document (`OCUE` magic) and the `.occues` cue-list interchange
/// file (`OCCU` magic). The plaintext inside is pretty-printed sorted-keys JSON.
/// AES-256-GCM gives confidentiality vs. casual snooping plus an auth tag
/// (tamper-evidence). The key is compiled into the binary and is extractable by
/// reverse-engineering — acceptable under the threat model in ADR-021.
enum CuelistCrypto {

    enum CryptoError: Error { case malformedEnvelope, unsupportedVersion, decryptionFailed }

    /// `.cuelist` document envelope magic.
    static let cuelistMagic = Data("OCUE".utf8)
    /// `.occues` cue-list interchange envelope magic.
    static let cueListExportMagic = Data("OCCU".utf8)

    private static let version: UInt8 = 0x01
    private static let magicLength = 4            // every magic is 4 ASCII bytes
    private static let nonceLength = 12           // AES-GCM nonce
    private static let tagLength = 16             // AES-GCM auth tag
    private static let headerLength = magicLength + 1 + nonceLength

    /// 32-byte fixed app key. Intentionally extractable (see ADR-021).
    private static let key = SymmetricKey(data: Data([
        0x4F, 0x6E, 0x6C, 0x79, 0x43, 0x75, 0x65, 0x2D,
        0x76, 0x31, 0x2D, 0x64, 0x6F, 0x63, 0x75, 0x6D,
        0x65, 0x6E, 0x74, 0x2D, 0x6B, 0x65, 0x79, 0x2D,
        0x41, 0x45, 0x53, 0x32, 0x35, 0x36, 0x47, 0x43
    ]))

    /// Seal `json` into the envelope identified by `magic`. Defaults to the
    /// `.cuelist` magic so existing document callers are unchanged.
    static func seal(_ json: Data, magic: Data = cuelistMagic) throws -> Data {
        let sealed = try AES.GCM.seal(json, using: key)
        var out = Data()
        out.append(magic)
        out.append(version)
        out.append(sealed.nonce.withUnsafeBytes { Data($0) })
        out.append(sealed.ciphertext)
        out.append(sealed.tag)
        return out
    }

    /// Open an envelope. `magic` selects the expected file type. When
    /// `allowLegacyPlaintext` is true (the `.cuelist` default), a file lacking
    /// the magic is returned unchanged — the pre-encryption `.cuelist` era. The
    /// `.occues` format has no such era and passes `false`.
    static func open(
        _ fileData: Data,
        magic: Data = cuelistMagic,
        allowLegacyPlaintext: Bool = true
    ) throws -> Data {
        let file = Data(fileData) // normalize to 0-based indices
        guard file.count >= magicLength, file.prefix(magicLength) == magic else {
            if allowLegacyPlaintext { return fileData }
            throw CryptoError.malformedEnvelope
        }
        guard file.count >= headerLength + tagLength else { throw CryptoError.malformedEnvelope }
        guard file[magicLength] == version else { throw CryptoError.unsupportedVersion }
        let nonceData = file.subdata(in: magicLength + 1 ..< magicLength + 1 + nonceLength)
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
            // Wrap CryptoKit failures (failed auth tag, bad nonce) into this
            // seam's own error domain so callers map every crypto failure to a
            // corrupt-file error in one place.
            throw CryptoError.decryptionFailed
        }
    }
}
