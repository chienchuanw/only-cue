using System.Security.Cryptography;
using System.Text;

namespace OnlyCue.Core;

/// <summary>Failure modes of <see cref="CuelistEnvelope"/>, mirroring the Swift
/// <c>CuelistCrypto.CryptoError</c> cases one-for-one.</summary>
public enum CuelistCryptoError
{
    MalformedEnvelope,
    UnsupportedVersion,
    DecryptionFailed
}

/// <summary>Raised for every envelope failure so callers map all of them to a
/// single corrupt-file error in one place, as the Swift seam does.</summary>
public sealed class CuelistCryptoException(CuelistCryptoError error)
    : Exception($"cuelist envelope error: {error}")
{
    public CuelistCryptoError Error { get; } = error;
}

/// <summary>
/// Seals/opens OnlyCue's encrypted envelopes — the C# half of Swift's
/// <c>CuelistCrypto</c> (epic #728, M1a). Two file types share the scheme: the
/// <c>.cuelist</c> document (<c>OCUE</c> magic) and the <c>.occues</c> cue-list
/// interchange file (<c>OCCU</c>). The plaintext inside is pretty-printed
/// sorted-keys JSON.
///
/// AES-256-GCM gives confidentiality vs. casual snooping plus an auth tag
/// (tamper-evidence). The key is compiled into the binary and is extractable by
/// reverse-engineering — accepted under ADR-021, and shipping it in a second
/// binary does not change that threat model.
///
/// Behaviour is pinned by <c>golden/cuelist-envelope-v1.json</c>. Note in
/// particular that a file whose magic does not match is returned *unchanged* when
/// <paramref name="allowLegacyPlaintext"/> is set — that is the pre-encryption
/// <c>.cuelist</c> era, and it means opening an <c>.occues</c> file as a document
/// yields raw ciphertext rather than an error. Faithful, not accidental.
/// </summary>
public static class CuelistEnvelope
{
    private const byte Version = 0x01;
    private const int MagicLength = 4;    // every magic is 4 ASCII bytes
    private const int NonceLength = 12;   // AES-GCM nonce
    private const int TagLength = 16;     // AES-GCM auth tag
    private const int HeaderLength = MagicLength + 1 + NonceLength;

    /// <summary><c>.cuelist</c> document envelope magic.</summary>
    public static byte[] CuelistMagic => "OCUE"u8.ToArray();

    /// <summary><c>.occues</c> cue-list interchange envelope magic.</summary>
    public static byte[] CueListExportMagic => "OCCU"u8.ToArray();

    /// <summary>32-byte fixed app key. Intentionally extractable (see ADR-021).</summary>
    private static readonly byte[] Key = Encoding.ASCII.GetBytes("OnlyCue-v1-document-key-AES256GC");

    /// <summary>Seal <paramref name="json"/> into the envelope identified by
    /// <paramref name="magic"/>. Output is non-deterministic: AES-GCM draws a
    /// fresh random nonce per call, which is why no golden vector pins it.</summary>
    public static byte[] Seal(byte[] json, byte[] magic)
    {
        ArgumentNullException.ThrowIfNull(json);
        ArgumentNullException.ThrowIfNull(magic);

        var nonce = RandomNumberGenerator.GetBytes(NonceLength);
        var ciphertext = new byte[json.Length];
        var tag = new byte[TagLength];

        using (var gcm = new AesGcm(Key, TagLength))
        {
            gcm.Encrypt(nonce, json, ciphertext, tag);
        }

        var output = new byte[MagicLength + 1 + NonceLength + ciphertext.Length + TagLength];
        var offset = 0;
        magic.CopyTo(output, offset);
        offset += MagicLength;
        output[offset++] = Version;
        nonce.CopyTo(output, offset);
        offset += NonceLength;
        ciphertext.CopyTo(output, offset);
        offset += ciphertext.Length;
        tag.CopyTo(output, offset);
        return output;
    }

    /// <summary>Open an envelope. <paramref name="magic"/> selects the expected
    /// file type. When <paramref name="allowLegacyPlaintext"/> is true (the
    /// <c>.cuelist</c> default), a file lacking the magic is returned unchanged —
    /// the pre-encryption era. The <c>.occues</c> format has no such era and
    /// passes false.</summary>
    public static byte[] Open(byte[] fileData, byte[] magic, bool allowLegacyPlaintext)
    {
        ArgumentNullException.ThrowIfNull(fileData);
        ArgumentNullException.ThrowIfNull(magic);

        if (fileData.Length < MagicLength
            || !fileData.AsSpan(0, MagicLength).SequenceEqual(magic))
        {
            return allowLegacyPlaintext
                ? fileData
                : throw new CuelistCryptoException(CuelistCryptoError.MalformedEnvelope);
        }

        if (fileData.Length < HeaderLength + TagLength)
        {
            throw new CuelistCryptoException(CuelistCryptoError.MalformedEnvelope);
        }

        if (fileData[MagicLength] != Version)
        {
            throw new CuelistCryptoException(CuelistCryptoError.UnsupportedVersion);
        }

        var nonce = fileData.AsSpan(MagicLength + 1, NonceLength);
        var body = fileData.AsSpan(HeaderLength);
        var ciphertext = body[..^TagLength];
        var tag = body[^TagLength..];
        var plaintext = new byte[ciphertext.Length];

        try
        {
            using var gcm = new AesGcm(Key, TagLength);
            gcm.Decrypt(nonce, ciphertext, tag, plaintext);
        }
        catch (CryptographicException)
        {
            // Wrap the failure (bad auth tag, bad nonce) into this seam's own
            // error domain so callers map every crypto failure to a corrupt-file
            // error in one place — same contract as the Swift side.
            throw new CuelistCryptoException(CuelistCryptoError.DecryptionFailed);
        }

        return plaintext;
    }
}
