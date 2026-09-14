using System.Text;
using Xunit;

namespace OnlyCue.Core.Tests;

/// <summary>
/// The Windows half of the <c>.cuelist</c> / <c>.occues</c> envelope contract
/// (epic #728, M1a). macOS emits <c>golden/cuelist-envelope-v1.json</c> from the
/// Swift <c>CuelistCrypto</c>; this suite asserts the C# re-implementation
/// reproduces every case exactly — including the cases that fail, and including
/// the legacy-plaintext passthrough that returns the input bytes unchanged.
/// </summary>
public class CuelistEnvelopeGoldenVectorTests
{
    private static readonly CuelistEnvelopeVector Vector = CuelistEnvelopeVector.Load();

    public static TheoryData<string> CaseNames
    {
        get
        {
            var data = new TheoryData<string>();
            foreach (var name in Vector.Cases.Select(c => c.Name))
            {
                data.Add(name);
            }

            return data;
        }
    }

    private static byte[] MagicFor(string name) => name switch
    {
        "OCUE" => CuelistEnvelope.CuelistMagic,
        "OCCU" => CuelistEnvelope.CueListExportMagic,
        _ => throw new InvalidDataException($"unknown envelope magic '{name}'")
    };

    [Fact]
    public void GoldenFile_IsTheExpectedContract()
    {
        Assert.Equal("cuelist-envelope", Vector.Contract);
        Assert.Equal(1, Vector.Version);
        Assert.NotEmpty(Vector.Cases);
    }

    [Theory]
    [MemberData(nameof(CaseNames))]
    public void CSharpCore_ReproducesGoldenCase(string name)
    {
        var goldenCase = Vector.Cases.Single(c => c.Name == name);
        var input = Convert.FromBase64String(goldenCase.InputBase64);
        var magic = MagicFor(goldenCase.Magic);

        if (!goldenCase.Expect.Ok)
        {
            var expected = goldenCase.Expect.Error switch
            {
                "malformedEnvelope" => CuelistCryptoError.MalformedEnvelope,
                "unsupportedVersion" => CuelistCryptoError.UnsupportedVersion,
                "decryptionFailed" => CuelistCryptoError.DecryptionFailed,
                var other => throw new InvalidDataException($"unknown golden error '{other}'")
            };

            var thrown = Assert.Throws<CuelistCryptoException>(
                () => CuelistEnvelope.Open(input, magic, goldenCase.AllowLegacyPlaintext));
            Assert.Equal(expected, thrown.Error);
            return;
        }

        var actual = CuelistEnvelope.Open(input, magic, goldenCase.AllowLegacyPlaintext);
        var expectedBytes = Convert.FromBase64String(
            goldenCase.Expect.OutputBase64
            ?? throw new InvalidDataException($"{name} is ok but has no outputBase64"));

        Assert.Equal(expectedBytes, actual);
    }

    /// <summary>
    /// <c>Seal</c> is deliberately absent from the vector: AES-GCM draws a fresh
    /// random nonce every call, so its output is not pinnable. It is pinned as a
    /// property instead — two seals differ, and both open back to the input. This
    /// mirrors <c>test_seal_roundTripsAndIsNonceRandomised</c> on the Swift side.
    /// </summary>
    [Fact]
    public void Seal_RoundTripsAndIsNonceRandomised()
    {
        var plaintext = Encoding.UTF8.GetBytes("{\"schemaVersion\":23}");

        foreach (var magicName in new[] { "OCUE", "OCCU" })
        {
            var magic = MagicFor(magicName);
            var first = CuelistEnvelope.Seal(plaintext, magic);
            var second = CuelistEnvelope.Seal(plaintext, magic);

            Assert.NotEqual(first, second);
            Assert.Equal(magic, first.Take(4).ToArray());

            foreach (var sealed_ in new[] { first, second })
            {
                Assert.Equal(plaintext, CuelistEnvelope.Open(sealed_, magic, false));
            }
        }
    }

    /// <summary>
    /// Cross-platform interop, the property the whole port rests on: an envelope
    /// this core seals must be openable by the Swift core, and vice versa. The
    /// vector's fixtures were produced by .NET and are proven to open under
    /// CryptoKit on the macOS side, so re-opening them here closes the loop.
    /// </summary>
    [Fact]
    public void SwiftSealedFixture_OpensHere()
    {
        var goldenCase = Vector.Cases.Single(c => c.Name == "openDocument");
        var opened = CuelistEnvelope.Open(
            Convert.FromBase64String(goldenCase.InputBase64),
            CuelistEnvelope.CuelistMagic,
            true);

        Assert.Contains("\"schemaVersion\" : 23", Encoding.UTF8.GetString(opened));
    }
}
