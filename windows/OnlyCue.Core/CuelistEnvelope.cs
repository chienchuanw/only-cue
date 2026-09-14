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

/// <summary>Stub — implemented once the golden verifier is red.</summary>
public static class CuelistEnvelope
{
    public static byte[] CuelistMagic => throw new NotImplementedException();

    public static byte[] CueListExportMagic => throw new NotImplementedException();

    public static byte[] Seal(byte[] json, byte[] magic)
        => throw new NotImplementedException();

    public static byte[] Open(byte[] fileData, byte[] magic, bool allowLegacyPlaintext)
        => throw new NotImplementedException();
}
