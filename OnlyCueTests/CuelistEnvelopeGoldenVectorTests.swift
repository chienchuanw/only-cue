import XCTest
@testable import OnlyCue

// Cross-platform golden-vector contract for the `.cuelist` / `.occues` crypto
// envelope (epic #728, M1a). macOS is the source of truth: it emits
// `golden/cuelist-envelope-v1.json`; the C# `OnlyCue.Core` re-implementation must
// reproduce every case exactly (verified on Windows CI).
//
// Why this contract exists at all: every OnlyCue document is sealed in AES-256-GCM
// (`CuelistCrypto`), so a Windows build that cannot open the envelope cannot open a
// single real file. The key is compiled into both binaries and is extractable —
// already accepted under ADR-021.
//
// Why the input envelopes are *committed literals* rather than generated here:
// `AES.GCM.seal` draws a fresh random nonce every call, so generating them would
// churn the vector on every run and pin nothing. The fixtures below were produced
// once with fixed nonces by .NET's `AesGcm` — which is the very implementation the
// C# core will use — so `test_fixtures_openWithTheSwiftImplementation` doubles as
// a CryptoKit↔.NET interop proof. `seal` itself is covered by a round-trip test.

// MARK: - Contract model (mirrored by the C# verifier's DTO)

struct CuelistEnvelopeGoldenVector: Codable, Equatable {
    let contract: String   // "cuelist-envelope"
    let version: Int       // 1
    let note: String
    let cases: [Case]

    struct Case: Codable, Equatable {
        let name: String
        let magic: String                 // "OCUE" | "OCCU" — which file type is expected
        let allowLegacyPlaintext: Bool
        let inputBase64: String
        let expect: Expect
    }

    struct Expect: Codable, Equatable {
        var ok: Bool
        /// Base64, not UTF-8 text: the legacy-passthrough cases return raw
        /// ciphertext bytes, which are not valid UTF-8.
        var outputBase64: String?
        /// "malformedEnvelope" | "unsupportedVersion" | "decryptionFailed"
        var error: String?
    }
}

// MARK: - Fixtures

/// Deterministic envelope fixtures. Generated once with fixed nonces; never
/// regenerated, so the committed vector is stable across runs.
enum CuelistEnvelopeFixture {

    /// A minimal but real v23 document, pretty-printed with sorted keys exactly
    /// as `CueListDocument.encodeModel` writes it.
    static let documentJSON = """
        {
          "id" : "6C7E2B90-1F4A-4C33-9E52-0A1B2C3D4E5F",
          "items" : [

          ],
          "name" : "Golden Vector Show",
          "schemaVersion" : 23
        }
        """

    /// Sealed `OCUE` envelope wrapping `documentJSON`.
    static let cuelistDocument = """
        T0NVRQEQERITFBUWFxgZGhvRYJZhMTkxv6CKI3dthvD/faDOBEcnsTH3SJsXTtNttOfz8isb\
        7F0kfDZOqv/9vQzGaYbmI9nNBrgTufhXGOiDc2CdHsJZqgBhiizhNeRBOWT2qmuJgqXgSm8d\
        YZcdVWPvns/HDE2P5UUSmcY4oWhCuFIXmlOkKo6o2qMZB4ggOJmaaqQTHtujsbfOwRZAYLk=
        """

    /// Sealed `OCCU` envelope wrapping the `.occues` interchange payload.
    static let cueListExport = """
        T0NDVQFAQUJDREVGR0hJSkvqFL2x3Vt5tbfI0vmLH556ZZ8htvNJuU0zfjMGDqQiRadv0d7C\
        89DKVPyWjsduqt6nM+f3kn1ZoQl0eHU=
        """
    static let cueListExportJSON = """
        {
          "cues" : [

          ],
          "formatVersion" : 1
        }
        """

    /// `cuelistDocument` with byte 0 changed `O` → `X`.
    static let badMagic = """
        WENVRQEQERITFBUWFxgZGhvRYJZhMTkxv6CKI3dthvD/faDOBEcnsTH3SJsXTtNttOfz8isb\
        7F0kfDZOqv/9vQzGaYbmI9nNBrgTufhXGOiDc2CdHsJZqgBhiizhNeRBOWT2qmuJgqXgSm8d\
        YZcdVWPvns/HDE2P5UUSmcY4oWhCuFIXmlOkKo6o2qMZB4ggOJmaaqQTHtujsbfOwRZAYLk=
        """

    /// `cuelistDocument` with the version byte changed `0x01` → `0x02`.
    static let badVersion = """
        T0NVRQIQERITFBUWFxgZGhvRYJZhMTkxv6CKI3dthvD/faDOBEcnsTH3SJsXTtNttOfz8isb\
        7F0kfDZOqv/9vQzGaYbmI9nNBrgTufhXGOiDc2CdHsJZqgBhiizhNeRBOWT2qmuJgqXgSm8d\
        YZcdVWPvns/HDE2P5UUSmcY4oWhCuFIXmlOkKo6o2qMZB4ggOJmaaqQTHtujsbfOwRZAYLk=
        """

    /// Right magic, 26 bytes — shorter than the 33-byte header+tag minimum.
    static let truncated = "T0NVRQEQERITFBUWFxgZGhvRYJY="

    /// `cuelistDocument` with the final auth-tag byte flipped.
    static let tamperedTag = """
        T0NVRQEQERITFBUWFxgZGhvRYJZhMTkxv6CKI3dthvD/faDOBEcnsTH3SJsXTtNttOfz8isb\
        7F0kfDZOqv/9vQzGaYbmI9nNBrgTufhXGOiDc2CdHsJZqgBhiizhNeRBOWT2qmuJgqXgSm8d\
        YZcdVWPvns/HDE2P5UUSmcY4oWhCuFIXmlOkKo6o2qMZB4ggOJmaaqQTHtujsbfOwRZAYEY=
        """

    /// `cuelistDocument` with a ciphertext byte flipped — GCM must reject this
    /// too, which is the tamper-evidence the envelope exists for.
    static let tamperedCiphertext = """
        T0NVRQEQERITFBUWFxgZGhsuYJZhMTkxv6CKI3dthvD/faDOBEcnsTH3SJsXTtNttOfz8isb\
        7F0kfDZOqv/9vQzGaYbmI9nNBrgTufhXGOiDc2CdHsJZqgBhiizhNeRBOWT2qmuJgqXgSm8d\
        YZcdVWPvns/HDE2P5UUSmcY4oWhCuFIXmlOkKo6o2qMZB4ggOJmaaqQTHtujsbfOwRZAYLk=
        """

    /// `documentJSON` with no envelope at all — the pre-encryption `.cuelist` era.
    static let legacyPlaintext = """
        ewogICJpZCIgOiAiNkM3RTJCOTAtMUY0QS00QzMzLTlFNTItMEExQjJDM0Q0RTVGIiwKICAi\
        aXRlbXMiIDogWwoKICBdLAogICJuYW1lIiA6ICJHb2xkZW4gVmVjdG9yIFNob3ciLAogICJz\
        Y2hlbWFWZXJzaW9uIiA6IDIzCn0=
        """
}

// MARK: - Generator (the Swift implementation IS the contract source of truth)

enum CuelistEnvelopeGolden {

    /// One probe: run `CuelistCrypto.open` and record what actually happened.
    private static func expect(
        input: String,
        magic: Data,
        allowLegacyPlaintext: Bool
    ) -> CuelistEnvelopeGoldenVector.Expect {
        guard let data = Data(base64Encoded: input) else {
            return .init(ok: false, outputBase64: nil, error: "malformedEnvelope")
        }
        do {
            let out = try CuelistCrypto.open(
                data, magic: magic, allowLegacyPlaintext: allowLegacyPlaintext
            )
            return .init(ok: true, outputBase64: out.base64EncodedString(), error: nil)
        } catch let error as CuelistCrypto.CryptoError {
            return .init(ok: false, outputBase64: nil, error: String(describing: error))
        } catch {
            return .init(ok: false, outputBase64: nil, error: "unknown")
        }
    }

    /// Every case is a `(fixture, expected magic, legacy policy)` triple. The
    /// cross-magic rows matter: opening an `.occues` file as a `.cuelist` hits the
    /// legacy-plaintext passthrough and returns the *ciphertext* rather than
    /// failing — surprising behaviour that the C# port must reproduce, not "fix".
    struct Probe {
        let name: String
        let fixture: String
        let magic: String
        let allowLegacyPlaintext: Bool
    }

    private static let probes: [Probe] = [
        Probe(name: "openDocument",
              fixture: CuelistEnvelopeFixture.cuelistDocument,
              magic: "OCUE", allowLegacyPlaintext: true),
        Probe(name: "openExport",
              fixture: CuelistEnvelopeFixture.cueListExport,
              magic: "OCCU", allowLegacyPlaintext: false),
        Probe(name: "legacyPlaintextPassesThrough",
              fixture: CuelistEnvelopeFixture.legacyPlaintext,
              magic: "OCUE", allowLegacyPlaintext: true),
        Probe(name: "legacyPlaintextRejectedForExport",
              fixture: CuelistEnvelopeFixture.legacyPlaintext,
              magic: "OCCU", allowLegacyPlaintext: false),
        Probe(name: "badMagicPassesThroughWhenLegacyAllowed",
              fixture: CuelistEnvelopeFixture.badMagic,
              magic: "OCUE", allowLegacyPlaintext: true),
        Probe(name: "badMagicRejectedWhenLegacyDisallowed",
              fixture: CuelistEnvelopeFixture.badMagic,
              magic: "OCUE", allowLegacyPlaintext: false),
        Probe(name: "documentOpenedAsExport",
              fixture: CuelistEnvelopeFixture.cuelistDocument,
              magic: "OCCU", allowLegacyPlaintext: false),
        Probe(name: "exportOpenedAsDocument",
              fixture: CuelistEnvelopeFixture.cueListExport,
              magic: "OCUE", allowLegacyPlaintext: true),
        Probe(name: "unsupportedVersion",
              fixture: CuelistEnvelopeFixture.badVersion,
              magic: "OCUE", allowLegacyPlaintext: true),
        Probe(name: "truncatedHeader",
              fixture: CuelistEnvelopeFixture.truncated,
              magic: "OCUE", allowLegacyPlaintext: true),
        Probe(name: "tamperedTag",
              fixture: CuelistEnvelopeFixture.tamperedTag,
              magic: "OCUE", allowLegacyPlaintext: true),
        Probe(name: "tamperedCiphertext",
              fixture: CuelistEnvelopeFixture.tamperedCiphertext,
              magic: "OCUE", allowLegacyPlaintext: true)
    ]

    private static func magicData(_ name: String) -> Data {
        name == "OCCU" ? CuelistCrypto.cueListExportMagic : CuelistCrypto.cuelistMagic
    }

    static func make() -> CuelistEnvelopeGoldenVector {
        CuelistEnvelopeGoldenVector(
            contract: "cuelist-envelope",
            version: 1,
            note: "macOS-generated golden vectors for the OnlyCue AES-256-GCM file "
                + "envelope (OCUE document / OCCU interchange). The C# OnlyCue.Core "
                + "re-implementation must reproduce every case exactly. `seal` is "
                + "deliberately absent: AES-GCM draws a random nonce, so it is not "
                + "pinnable — it is covered by a round-trip test on each platform. "
                + "To regenerate after a deliberate CuelistCrypto change, delete "
                + "golden/cuelist-envelope-v1.json and re-run the test suite.",
            cases: probes.map { probe in
                CuelistEnvelopeGoldenVector.Case(
                    name: probe.name,
                    magic: probe.magic,
                    allowLegacyPlaintext: probe.allowLegacyPlaintext,
                    inputBase64: probe.fixture,
                    expect: expect(
                        input: probe.fixture,
                        magic: magicData(probe.magic),
                        allowLegacyPlaintext: probe.allowLegacyPlaintext
                    )
                )
            }
        )
    }

    /// Deterministic encoding so the committed file is stable and diff-friendly.
    static func encoded(_ vector: CuelistEnvelopeGoldenVector) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(vector)
    }
}

// MARK: - Tests

final class CuelistEnvelopeGoldenVectorTests: XCTestCase {

    private func goldenURL() throws -> URL {
        try repoRoot().appendingPathComponent("golden", isDirectory: true)
            .appendingPathComponent("cuelist-envelope-v1.json")
    }

    /// Independent pins that do not go through the generator, so a broken
    /// `CuelistCrypto` fails here rather than silently baking wrong "golden"
    /// values. Also proves the .NET-produced fixtures open under CryptoKit —
    /// the cross-platform property the whole port depends on.
    func test_fixtures_openWithTheSwiftImplementation() throws {
        let document = try XCTUnwrap(Data(base64Encoded: CuelistEnvelopeFixture.cuelistDocument))
        let opened = try CuelistCrypto.open(document)
        XCTAssertEqual(
            String(decoding: opened, as: UTF8.self),
            CuelistEnvelopeFixture.documentJSON,
            "the committed OCUE fixture must decrypt to the documented plaintext"
        )

        let export = try XCTUnwrap(Data(base64Encoded: CuelistEnvelopeFixture.cueListExport))
        let openedExport = try CuelistCrypto.open(
            export, magic: CuelistCrypto.cueListExportMagic, allowLegacyPlaintext: false
        )
        XCTAssertEqual(
            String(decoding: openedExport, as: UTF8.self),
            CuelistEnvelopeFixture.cueListExportJSON
        )
    }

    /// The tamper-evidence the envelope exists for: flipping any byte of the
    /// ciphertext or the tag must fail the GCM auth check, not return garbage.
    func test_tamperedEnvelopes_areRejected() throws {
        for fixture in [
            CuelistEnvelopeFixture.tamperedTag,
            CuelistEnvelopeFixture.tamperedCiphertext
        ] {
            let data = try XCTUnwrap(Data(base64Encoded: fixture))
            XCTAssertThrowsError(try CuelistCrypto.open(data)) { error in
                XCTAssertEqual(error as? CuelistCrypto.CryptoError, .decryptionFailed)
            }
        }
    }

    /// `seal` cannot be vector-pinned (random nonce), so it is pinned as a
    /// property instead: two seals of the same input differ, and both open back
    /// to the input.
    func test_seal_roundTripsAndIsNonceRandomised() throws {
        let plaintext = Data(CuelistEnvelopeFixture.documentJSON.utf8)

        for magic in [CuelistCrypto.cuelistMagic, CuelistCrypto.cueListExportMagic] {
            let first = try CuelistCrypto.seal(plaintext, magic: magic)
            let second = try CuelistCrypto.seal(plaintext, magic: magic)
            XCTAssertNotEqual(first, second, "AES-GCM must not reuse a nonce")
            XCTAssertEqual(first.prefix(4), magic)
            for sealed in [first, second] {
                let reopened = try CuelistCrypto.open(
                    sealed, magic: magic, allowLegacyPlaintext: false
                )
                XCTAssertEqual(reopened, plaintext)
            }
        }
    }

    /// Drift guard + bootstrap, mirroring `TimecodeGoldenVectorTests`. A missing
    /// file is written and the test fails, so a contract change is always
    /// committed and reviewed rather than silently accepted in CI.
    func test_committedVectors_matchCurrentSwiftOutput() throws {
        let url = try goldenURL()
        let generated = try CuelistEnvelopeGolden.encoded(CuelistEnvelopeGolden.make())

        guard FileManager.default.fileExists(atPath: url.path) else {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try generated.write(to: url)
            return XCTFail("golden/cuelist-envelope-v1.json was missing — generated it from "
                + "the Swift CuelistCrypto implementation. Commit the file and re-run. (To "
                + "regenerate after a deliberate change, delete the file first.)")
        }

        let committed = try JSONDecoder().decode(
            CuelistEnvelopeGoldenVector.self, from: Data(contentsOf: url)
        )
        XCTAssertEqual(
            committed,
            CuelistEnvelopeGolden.make(),
            "golden/cuelist-envelope-v1.json drifted from the Swift CuelistCrypto "
                + "implementation. If the change was intentional, delete the file and re-run "
                + "to regenerate, review the diff, and update the C# OnlyCue.Core to match."
        )
    }
}
