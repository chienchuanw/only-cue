# `.cuelist` Encryption + "OnlyCue Document" Kind — Design

**Date:** 2026-05-19
**Status:** Approved
**Amends:** ADR-006 (JSON `.cuelist` document with referenced media)
**New ADR:** ADR-021

## 1. Goal & threat model

Two user-facing goals:

1. A saved `.cuelist` must not be readable in a text editor by a casual person, and must be **tamper-evident** (the app detects out-of-app modification).
2. Finder's **Kind** column shows **"OnlyCue Document"** for `.cuelist` files.

**In scope (threat model):** stop casual snooping / protect show IP from someone who merely opens the file; detect tampering.

**Explicitly out of scope:** confidentiality against an attacker who reverse-engineers the app binary; per-document passwords; per-machine key isolation; lost/stolen-laptop at-rest defense (FileVault's job). Files remain **portable** (any OnlyCue install opens any file) and **open transparently** (no password prompt — compatible with `DocumentGroup` open/recents/autosave).

## 2. Cryptography

- **AES-256-GCM** via CryptoKit (`AES.GCM`). GCM provides confidentiality plus a 16-byte authentication tag, so tamper-evidence is intrinsic: any modification makes `AES.GCM.open` throw.
- **Fixed 256-bit key** compiled into the app as a `static let` 32-byte key. No obfuscation theater. ADR-021 states plainly that the key is extractable from the binary and that this is acceptable under the stated threat model.
- **Fresh random 12-byte nonce per save** (CryptoKit's default `AES.GCM.Nonce()`).

## 3. File envelope

A small binary envelope enables legacy detection and format versioning:

```
offset  bytes  field
0       4      magic       ASCII "OCUE"
4       1      version     0x01
5       12     nonce       AES-GCM nonce
17      ...    payload     ciphertext + 16-byte GCM tag
```

The plaintext inside the envelope is exactly today's output: pretty-printed, sorted-keys JSON encoding of `ProjectModel`. The schema/migration machinery is therefore **untouched** — it continues to operate on JSON after decryption.

## 4. Code seam

One new isolated, pure, unit-testable value type: `OnlyCue/Document/CuelistCrypto.swift`.

```
enum CuelistCrypto {
    static func seal(_ json: Data) throws -> Data   // magic+version+nonce+ciphertext+tag
    static func open(_ file: Data) throws -> Data    // magic present → decrypt to JSON
                                                     // magic absent  → return file unchanged (legacy)
}
```

Wire into the two existing chokepoints in `OnlyCue/Document/CueListDocument.swift` only:

- `init(configuration:)`:
  `self.model = try ProjectModel.decode(from: CuelistCrypto.open(data))`
- `fileWrapper(snapshot:configuration:)`:
  `FileWrapper(regularFileWithContents: try CuelistCrypto.seal(encodedJSON))`

`ProjectModel+Migration.swift` and `ProjectModel.decode(from:)` are **not modified**.

**Legacy migration:** an existing plaintext `.cuelist` has no `OCUE` magic, so `open` returns the bytes unchanged and the existing JSON/migration path loads it normally. The next save re-writes it encrypted. No user action, no prompt.

**Error mapping:** a present-but-invalid envelope (truncated, wrong version, failed auth tag) throws; `CueListDocument.init(configuration:)` surfaces it as `CocoaError(.fileReadCorruptFile)`, consistent with the existing corrupt-file path.

## 5. Kind column → "OnlyCue Document"

In `OnlyCue/Resources/Info.plist`:

- `UTExportedTypeDeclarations` → `UTTypeDescription`: `OnlyCue Cue List` → **`OnlyCue Document`**
- `CFBundleDocumentTypes` → `CFBundleTypeName`: `OnlyCue Cue List` → **`OnlyCue Document`**
- `UTTypeConformsTo`: `public.json` → **`public.data`** (the file is no longer JSON; this also removes the "JSON document" Kind ambiguity)
- Remove the `public.mime-type` `application/json` tag from `UTTypeTagSpecification`.
- `public.filename-extension` stays `cuelist`; `UTTypeIdentifier`/`LSItemContentTypes` stay `com.onlycue.cuelist`.
- `CueListDocument.swift`: `UTType(exportedAs: "com.onlycue.cuelist")` unchanged.

Operational notes:

- Info.plist changed → must run `xcodegen generate`.
- LaunchServices caches Kind strings. Existing dev installs may show a stale Kind until an `lsregister` rebuild or a clean install; fresh installs are correct. This is a known macOS behavior, not a code defect — note it in the PR verification block, do not engineer around it.

## 6. Testing (TDD)

Pure unit tests on `CuelistCrypto` (no AVFoundation/UI dependency, fast suite):

1. **Round-trip:** `open(seal(x)) == x` for representative JSON payloads (incl. empty and large).
2. **Legacy passthrough:** `open(plaintextJSON)` returns the input unchanged when no `OCUE` magic is present.
3. **Tamper-evidence:** flipping any byte of ciphertext or tag makes `open` throw.
4. **Malformed envelope:** truncated (< 17 bytes), unknown version byte, or garbage-with-magic throws cleanly.

Document-level tests:

5. Round-trip a populated `ProjectModel` through `fileWrapper` → `init(configuration:)`; assert equality.
6. Load a committed **legacy plaintext fixture** `.cuelist`; assert it loads, then assert re-saving produces an `OCUE`-magic (encrypted) file.

## 7. Documentation

- **ADR-021** — "Encrypted `.cuelist` container; fixed app key (obfuscation + tamper-evidence, not vendor-proof confidentiality)". Records: the chosen threat model, the extractable-key limitation stated honestly, the loss of git-diffability/inspectability, and that it amends ADR-006.
- **ADR-006** — set Status to "Amended by ADR-021".
- **`docs/data-model.md`** — remove the "Pretty-printed, keys sorted, so files diff cleanly under git" claim for the on-disk file; document the `OCUE` envelope; clarify that the JSON described is the *decrypted* payload.

## 8. Out of scope (YAGNI)

Passwords, key rotation, Keychain, per-machine keys, a debug/plaintext escape-hatch mode, compression. None are required by the chosen threat model and each adds tested code paths or breaks portability/transparent-open.

## 9. Build sequence (for the implementation plan)

1. `CuelistCrypto` + its pure unit tests (TDD, red→green).
2. Wire `CueListDocument` read/write to `CuelistCrypto`; add document round-trip + legacy-fixture tests (commit a legacy plaintext fixture).
3. `Info.plist` Kind/UTType changes; `xcodegen generate`.
4. ADR-021 + ADR-006 status + `data-model.md` updates.
