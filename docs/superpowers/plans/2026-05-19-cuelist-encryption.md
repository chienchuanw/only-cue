# `.cuelist` Encryption + "OnlyCue Document" Kind — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Encrypt `.cuelist` files with AES-256-GCM (casual-snoop + tamper-evidence), keep legacy plaintext files readable, and make Finder show "OnlyCue Document" in the Kind column.

**Architecture:** A pure `CuelistCrypto` value type seals/opens an `OCUE`-magic binary envelope around the existing pretty-printed JSON. `CueListDocument`'s read/write paths delegate through two thin testable static helpers (`decodeModel`/`encodeModel`) so the schema/migration machinery is untouched and the seam is unit-testable without `ReadConfiguration`/`WriteConfiguration`. `Info.plist` UTType metadata changes drive the Kind column.

**Tech Stack:** Swift, CryptoKit (`AES.GCM`), XCTest, XcodeGen.

Spec: `docs/superpowers/specs/2026-05-19-cuelist-encryption-design.md`

**Conventions used in this plan:**

- Regenerate the Xcode project after adding any new file: `xcodegen generate` (sources are folder-based; new files need a project regen).
- Test command form: `xcodebuild test -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/<Class> 2>&1 | tail -25`
- Branch: this is issue work — create `issues/<N>` off `dev` first if not already on it (per project CLAUDE.md). Commits use Conventional Commits, lowercase, no `Co-Authored-By` trailer.

---

### Task 1: `CuelistCrypto` value type (pure, TDD)

**Files:**

- Create: `OnlyCue/Document/CuelistCrypto.swift`
- Test: `OnlyCueTests/CuelistCryptoTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `OnlyCueTests/CuelistCryptoTests.swift`:

```swift
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

    func test_open_tamperedCiphertext_throws() throws {
        var sealed = try CuelistCrypto.seal(Data("hello world".utf8))
        sealed[sealed.count - 1] ^= 0xFF // flip a tag byte
        XCTAssertThrowsError(try CuelistCrypto.open(sealed))
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodegen generate && xcodebuild test -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/CuelistCryptoTests 2>&1 | tail -25`
Expected: FAIL — compilation error, `CuelistCrypto` is undefined.

- [ ] **Step 3: Write the implementation**

Create `OnlyCue/Document/CuelistCrypto.swift`:

```swift
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
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodegen generate && xcodebuild test -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/CuelistCryptoTests 2>&1 | tail -25`
Expected: PASS — all 6 tests green. (If a SwiftLint pre-build step flags the byte-array literal, that's fine — it's `warning`-level, not error, in Debug.)

- [ ] **Step 5: Commit**

```bash
xcodegen generate
git add OnlyCue/Document/CuelistCrypto.swift OnlyCueTests/CuelistCryptoTests.swift
git commit -m "feat(document): add CuelistCrypto AES-GCM envelope with legacy passthrough"
```

---

### Task 2: Wire `CueListDocument` read/write through the crypto seam

**Files:**

- Modify: `OnlyCue/Document/CueListDocument.swift:43-59`
- Test: `OnlyCueTests/CueListDocumentTests.swift` (append to existing file)

- [ ] **Step 1: Write the failing tests**

Append these methods inside the existing `final class CueListDocumentTests` in `OnlyCueTests/CueListDocumentTests.swift` (keep the existing `test_initEmpty_...` test):

```swift
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodegen generate && xcodebuild test -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/CueListDocumentTests 2>&1 | tail -25`
Expected: FAIL — `CueListDocument` has no `encodeModel`/`decodeModel` members.

- [ ] **Step 3: Modify `CueListDocument` to add the seam helpers and use them**

In `OnlyCue/Document/CueListDocument.swift`, replace the body of `init(configuration:)` and `fileWrapper(...)` and add two static helpers. The final file's lines 43–60 region becomes:

```swift
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        do {
            self.model = try Self.decodeModel(from: data)
        } catch is CuelistCrypto.CryptoError {
            throw CocoaError(.fileReadCorruptFile)
        }
    }

    func snapshot(contentType: UTType) throws -> ProjectModel {
        model
    }

    func fileWrapper(snapshot: ProjectModel, configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try Self.encodeModel(snapshot))
    }

    /// Decrypt (or pass through a legacy plaintext file) then run schema migration.
    static func decodeModel(from fileData: Data) throws -> ProjectModel {
        try ProjectModel.decode(from: CuelistCrypto.open(fileData))
    }

    /// Encode to pretty JSON, then seal in the encrypted envelope.
    static func encodeModel(_ model: ProjectModel) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try CuelistCrypto.seal(try encoder.encode(model))
    }
```

Leave lines 1–42 (imports, `UTType.cueList`, the class declaration, the `init()` and `initialCuePointTypes()` members) unchanged.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild test -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/CueListDocumentTests 2>&1 | tail -25`
Expected: PASS — the existing `test_initEmpty_...` plus the 3 new tests are green.

- [ ] **Step 5: Run the full unit suite to check for regressions**

Run: `xcodebuild test -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests 2>&1 | tail -25`
Expected: PASS — no regressions (any test that round-trips through `snapshot`/encode now goes through encryption transparently).

- [ ] **Step 6: Commit**

```bash
git add OnlyCue/Document/CueListDocument.swift OnlyCueTests/CueListDocumentTests.swift
git commit -m "feat(document): seal .cuelist on save, read legacy plaintext transparently"
```

---

### Task 3: `Info.plist` — "OnlyCue Document" Kind + non-JSON UTType

**Files:**

- Modify: `OnlyCue/Resources/Info.plist:30-31` and `:44-67`

- [ ] **Step 1: Edit `CFBundleTypeName`**

In `OnlyCue/Resources/Info.plist`, change:

```xml
            <key>CFBundleTypeName</key>
            <string>OnlyCue Cue List</string>
```

to:

```xml
            <key>CFBundleTypeName</key>
            <string>OnlyCue Document</string>
```

- [ ] **Step 2: Edit the exported type declaration**

Replace the entire `UTExportedTypeDeclarations` array (lines 44–67) with:

```xml
    <key>UTExportedTypeDeclarations</key>
    <array>
        <dict>
            <key>UTTypeConformsTo</key>
            <array>
                <string>public.data</string>
            </array>
            <key>UTTypeDescription</key>
            <string>OnlyCue Document</string>
            <key>UTTypeIdentifier</key>
            <string>com.onlycue.cuelist</string>
            <key>UTTypeTagSpecification</key>
            <dict>
                <key>public.filename-extension</key>
                <array>
                    <string>cuelist</string>
                </array>
            </dict>
        </dict>
    </array>
```

(Changes: `public.json` → `public.data`; description → `OnlyCue Document`; the `public.mime-type` `application/json` tag is removed. `UTTypeIdentifier` and the `cuelist` extension are unchanged.)

- [ ] **Step 3: Regenerate the project and build**

Run: `xcodegen generate && xcodebuild build -scheme OnlyCue -destination 'platform=macOS' 2>&1 | tail -15`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Manually verify the Kind column**

Run: `xcodebuild build -scheme OnlyCue -destination 'platform=macOS' -derivedDataPath build/dd 2>&1 | tail -3 && open -R build/dd/Build/Products/Debug/OnlyCue.app`
Then, in a scratch dir: launch the built app, create + save a new document as `~/Desktop/kind-check.cuelist`, and in Finder check the **Kind** column / Get Info → it must read **"OnlyCue Document"**.
Note: LaunchServices caches Kind strings. If it shows a stale value, run `/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f build/dd/Build/Products/Debug/OnlyCue.app` and re-check. A stale Kind on a dev machine is not a code defect — record it as a known caveat in the PR verification block. Also confirm the saved file is not readable as text (`file ~/Desktop/kind-check.cuelist` → "data", and it is not valid JSON).

- [ ] **Step 5: Commit**

```bash
git add OnlyCue/Resources/Info.plist
git commit -m "feat(document): kind column reads \"OnlyCue Document\"; declare as public.data"
```

---

### Task 4: Documentation — ADR-021, ADR-006 status, data-model

**Files:**

- Modify: `docs/decisions.md` (add ADR-021 above ADR-020; amend ADR-006 status)
- Modify: `docs/data-model.md:3-7`

- [ ] **Step 1: Add ADR-021**

In `docs/decisions.md`, insert directly above the `## ADR-020` line:

```markdown
## ADR-021 — Encrypted `.cuelist` container with a fixed app key (obfuscation + tamper-evidence, not vendor-proof confidentiality)
**Date**: 2026-05-19
**Status**: Accepted
**Amends**: ADR-006
**Decision**: A `.cuelist` is written as a binary envelope — ASCII magic `OCUE`, a 1-byte format version (`0x01`), a 12-byte AES-GCM nonce, then AES-256-GCM ciphertext + 16-byte tag — wrapping the same pretty-printed, sorted-keys JSON encoding of `ProjectModel` used before. Encryption uses CryptoKit `AES.GCM` with a single 256-bit key compiled into the app binary. Reading detects the absence of the `OCUE` magic and passes pre-encryption plaintext files through to the existing JSON/migration path unchanged; the next save re-writes them encrypted. The crypto lives in one pure value type (`CuelistCrypto`) consumed only by `CueListDocument`'s `decodeModel`/`encodeModel` seam; `ProjectModel` schema migration is untouched.
**Why**: The owner wants show IP protected from casual snooping (no opening a `.cuelist` in a text editor) and wants tamper-evidence, but explicitly does *not* want per-document passwords or per-machine key isolation — files must stay portable and open transparently under `DocumentGroup` (no prompt, recents/autosave intact). AES-GCM gives confidentiality plus an authentication tag (tampering ⇒ decryption throws) in one primitive. A fixed in-binary key is the only key strategy that satisfies "portable + transparent open" without a password UX; it is honestly limited — anyone who reverse-engineers the app can extract the key — but that attacker is outside the stated threat model. Keeping the plaintext-inside identical to the old format means the v1→v12 migration chain and all model code are unaffected, and legacy files keep opening.
**Reversal cost**: Low. `CuelistCrypto` is one self-contained file; `decodeModel`/`encodeModel` are two thin helpers. Removing encryption is deleting the seal call (saved files would revert to plaintext on next save) — legacy passthrough already reads both. The one load-bearing commitment is the `OCUE`/version envelope shape once files exist in the wild; the version byte exists precisely so a future format (key rotation, a different cipher) is an additive `open` branch, not a breaking change.
```

- [ ] **Step 2: Amend ADR-006 status**

In `docs/decisions.md`, under `## ADR-006 — JSON`.cuelist`document with referenced media`, change the `**Status**: Accepted` line for that ADR to:

```markdown
**Status**: Accepted (amended by ADR-021 — the on-disk file is now an encrypted envelope around this JSON; the "diffs cleanly under git / inspectable" benefit no longer applies to saved files)
```

- [ ] **Step 3: Update `docs/data-model.md`**

In `docs/data-model.md`, replace lines 3–7 (the `##`.cuelist`file` heading and the two sentences under it) with:

```markdown
## `.cuelist` file

A `.cuelist` is an encrypted binary container (see ADR-021): ASCII magic `OCUE`, a
1-byte format version, a 12-byte AES-GCM nonce, then AES-256-GCM ciphertext + tag.
The **decrypted payload** is a UTF-8 JSON document, pretty-printed with sorted keys.
Saved files are therefore *not* git-diffable or text-inspectable; the JSON shape
documented below is what you get after decryption. Pre-encryption plaintext
`.cuelist` files still open (detected by the absent `OCUE` magic) and are
re-written encrypted on the next save.

UTType: `com.onlycue.cuelist`, conforms to `public.data`. Finder Kind: "OnlyCue Document".
```

- [ ] **Step 4: Commit**

```bash
git add docs/decisions.md docs/data-model.md
git commit -m "docs: ADR-021 encrypted .cuelist container; amend ADR-006 + data-model"
```

---

## Self-Review

**Spec coverage:**

- §2 Crypto (AES-256-GCM, fixed key, per-save nonce) → Task 1.
- §3 Envelope (`OCUE`+version+nonce+ct+tag) → Task 1 (`seal`).
- §4 Code seam (`CuelistCrypto`, `CueListDocument` two chokepoints, migration untouched, legacy passthrough, error → `CocoaError(.fileReadCorruptFile)`) → Task 1 + Task 2.
- §5 Kind/UTType (`UTTypeDescription`, `CFBundleTypeName`, `public.json`→`public.data`, drop mime tag, extension unchanged, xcodegen, LaunchServices caveat) → Task 3.
- §6 Testing (round-trip, legacy passthrough, tamper, malformed, document round-trip, legacy fixture) → Task 1 tests + Task 2 tests. (The legacy "fixture" is generated inline by encoding a `ProjectModel` to plaintext JSON, matching this repo's inline-fixture convention rather than a bundled resource file.)
- §7 Docs (ADR-021, ADR-006 amended, data-model.md) → Task 4.
- §9 Build sequence order → Tasks 1→2→3→4 match.

**Placeholder scan:** none — every code/edit step shows the literal content.

**Type consistency:** `CuelistCrypto.seal`/`open`, `CuelistCrypto.CryptoError`, `CueListDocument.decodeModel(from:)`/`encodeModel(_:)` are named identically across Tasks 1–4 and the spec.

No gaps found.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-05-19-cuelist-encryption.md`. Two execution options:

1. **Subagent-Driven (recommended)** — a fresh subagent per task, two-stage review between tasks, fast iteration.
2. **Inline Execution** — execute tasks in this session with checkpoints for review.

Which approach?
