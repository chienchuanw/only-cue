# Portable Cue Lists (.occues) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user export one song's cue list from an OnlyCue project to a portable `.occues` file and import it onto a song in another project as a starting point.

**Architecture:** A new encrypted interchange file (`.occues`, `OCCU` magic) reusing the existing `CuelistCrypto` envelope. All pure logic — encode/decode, type reconciliation, cue reconciliation, media matching — lives in a testable `CueListTransfer` enum. Model writes go through one new undoable command `CueCommands.importCueList`. AppKit panels/alerts live in a thin `CueTransferAction`, wired to the Cue menu via a `NotificationCenter` + `ViewModifier` receiver, exactly like the existing `TemplateAction` / `TemplateMenuReceiver` pair. `ProjectModel` and `schemaVersion` are untouched.

**Tech Stack:** Swift 5.10, SwiftUI + AppKit, CryptoKit (AES-256-GCM), XCTest, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-05-22-cue-list-export-import-design.md`

---

## Conventions used in every task

**Test command** (run after every code change — `xcodegen generate` picks up new files, and is idempotent/cheap):

```bash
xcodegen generate && xcodebuild test \
  -project OnlyCue.xcodeproj -scheme OnlyCue \
  -destination 'platform=macOS' \
  -only-testing:OnlyCueTests/<TestClassName> 2>&1 | xcbeautify
```

**Full build** (for UI-glue tasks with no unit test):

```bash
xcodegen generate && xcodebuild build \
  -project OnlyCue.xcodeproj -scheme OnlyCue \
  -configuration Debug -destination 'platform=macOS' 2>&1 | xcbeautify
```

**Commit style:** Conventional Commits, lowercase after prefix, imperative. **No `Co-Authored-By` trailers.** One commit per task (failing test + implementation together).

**Branch:** all work happens on the feature/issue branch (created by the execution skill), never committed directly to `dev`.

---

## File structure

**New files**

| File | Responsibility |
|---|---|
| `OnlyCue/Commands/CueListTransfer.swift` | `.occues` payload structs, JSON+crypto codec, `makeExport`, `mediaMatches`, `reconcileTypes`, `reconcileCues`. Pure, no AppKit. |
| `OnlyCue/Commands/CueCommands+Transfer.swift` | `CueCommands.importCueList` — the one undoable command. |
| `OnlyCue/UI/CueTransferAction.swift` | AppKit glue: `NSSavePanel` / `NSOpenPanel`, mismatch + conflict `NSAlert`s. Mirrors `TemplateAction`. |
| `OnlyCue/UI/CueTransferMenuReceiver.swift` | `ViewModifier` routing the two menu notifications to `CueTransferAction`. Mirrors `TemplateMenuReceiver`. |
| `OnlyCueTests/CueListTransferTests.swift` | Unit tests for `CueListTransfer`. |
| `OnlyCueTests/CueCommandsTransferTests.swift` | Unit tests for `importCueList` + undo. |
| `OnlyCueUITests/CueTransferMenuUITests.swift` | UITest: the two Cue-menu items exist. |

**Modified files**

| File | Change |
|---|---|
| `OnlyCue/Document/CuelistCrypto.swift` | Parameterize `seal`/`open` by `magic`; add `cueListExportMagic`; add `allowLegacyPlaintext` flag. |
| `OnlyCue/Commands/CueCommands+Types.swift` | Change `mutateProject` from `fileprivate` to `internal`. |
| `OnlyCue/Document/CueListDocument.swift` | Add `UTType.cueListExport`. |
| `OnlyCue/Resources/Info.plist` | Add a `UTExportedTypeDeclarations` entry for `com.onlycue.cues`. |
| `OnlyCue/App/AppCommands.swift` | Add `Export Cue List…` / `Import Cue List…` to the Cue menu. |
| `OnlyCue/UI/DocumentView.swift` | Add two `Notification.Name`s; apply `.cueTransferMenuReceiver(...)`. |
| `OnlyCueTests/CuelistCryptoTests.swift` | Add tests for the magic parameter. |

---

## Task 1: Parameterize `CuelistCrypto` by magic

The `.occues` container reuses the AES-256-GCM envelope but needs a distinct `OCCU`
magic and must reject the legacy-plaintext fallback. Make `seal`/`open` accept a
`magic`; default it to `OCUE` so every existing `.cuelist` caller is unchanged.

**Files:**

- Modify: `OnlyCue/Document/CuelistCrypto.swift`
- Test: `OnlyCueTests/CuelistCryptoTests.swift`

- [ ] **Step 1: Write the failing tests**

Append these to `OnlyCueTests/CuelistCryptoTests.swift`, inside the `final class CuelistCryptoTests` body:

```swift
    func test_seal_withExportMagic_roundTrips() throws {
        let payload = Data(#"{"formatVersion":1}"#.utf8)
        let sealed = try CuelistCrypto.seal(payload, magic: CuelistCrypto.cueListExportMagic)
        XCTAssertEqual(sealed.prefix(4), Data("OCCU".utf8), "export envelope must start with OCCU")
        XCTAssertEqual(
            try CuelistCrypto.open(sealed, magic: CuelistCrypto.cueListExportMagic),
            payload
        )
    }

    func test_open_exportMagic_rejectsCuelistEnvelope() throws {
        // A .cuelist (OCUE) opened as an export (OCCU), with no legacy fallback,
        // must be a malformed envelope — not a silent plaintext pass-through.
        let cuelist = try CuelistCrypto.seal(Data("x".utf8)) // default OCUE
        XCTAssertThrowsError(
            try CuelistCrypto.open(cuelist, magic: CuelistCrypto.cueListExportMagic, allowLegacyPlaintext: false)
        ) { error in
            XCTAssertEqual(error as? CuelistCrypto.CryptoError, .malformedEnvelope)
        }
    }

    func test_open_exportMagic_rejectsBareJSON() {
        let bareJSON = Data(#"{"formatVersion":1}"#.utf8)
        XCTAssertThrowsError(
            try CuelistCrypto.open(bareJSON, magic: CuelistCrypto.cueListExportMagic, allowLegacyPlaintext: false)
        ) { error in
            XCTAssertEqual(error as? CuelistCrypto.CryptoError, .malformedEnvelope)
        }
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodegen generate && xcodebuild test -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/CuelistCryptoTests 2>&1 | xcbeautify`
Expected: compile failure — `cueListExportMagic` and the `magic:` / `allowLegacyPlaintext:` parameters do not exist yet.

- [ ] **Step 3: Rewrite `CuelistCrypto.swift`**

Replace the entire body of `OnlyCue/Document/CuelistCrypto.swift` with:

```swift
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodegen generate && xcodebuild test -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/CuelistCryptoTests 2>&1 | xcbeautify`
Expected: PASS — all original `CuelistCryptoTests` (unchanged via the `OCUE` default) plus the 3 new tests.

- [ ] **Step 5: Commit**

```bash
git add OnlyCue/Document/CuelistCrypto.swift OnlyCueTests/CuelistCryptoTests.swift
git commit -m "refactor(document): parameterize CuelistCrypto envelope magic"
```

---

## Task 2: `.occues` payload model + codec

Define the payload structs and the JSON+crypto codec. `decode` probes
`formatVersion` first so an unknown version yields a precise error.

**Files:**

- Create: `OnlyCue/Commands/CueListTransfer.swift`
- Test: `OnlyCueTests/CueListTransferTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `OnlyCueTests/CueListTransferTests.swift`:

```swift
import XCTest
@testable import OnlyCue

final class CueListTransferTests: XCTestCase {

    // MARK: fixtures

    private func sampleType(name: String = "Spotlight", hotkey: Int? = 3) -> CuePointType {
        CuePointType(
            id: UUID(),
            name: name,
            colorHex: "#4ECDC4",
            defaultFadeTime: 0,
            defaultNamePattern: "Cue",
            hotkey: hotkey,
            isVisible: true,
            isExportEnabled: true
        )
    }

    private func sampleCue(typeID: UUID, number: Double? = 1) -> Cue {
        Cue(
            id: UUID(),
            typeID: typeID,
            cueNumber: number,
            name: "Spot up SR",
            time: 4.25,
            notes: "Wait for breath",
            fadeTime: FadeTime(fadeIn: 1.5, fadeOut: 1.5)
        )
    }

    private func sampleExport() -> CueListExport {
        let type = sampleType()
        return CueListExport(
            formatVersion: CueListTransfer.currentFormatVersion,
            exportedAt: Date(timeIntervalSince1970: 1_700_000_000),
            sourceMedia: ExportedSourceMedia(displayName: "act1.wav", duration: 184.32),
            cuePointTypes: [type],
            cues: [sampleCue(typeID: type.id)]
        )
    }

    // MARK: tests

    func test_encode_then_decode_roundTrips() throws {
        let original = sampleExport()
        let data = try CueListTransfer.encode(original)
        XCTAssertEqual(data.prefix(4), Data("OCCU".utf8), ".occues must start with the OCCU magic")
        let decoded = try CueListTransfer.decode(data)
        XCTAssertEqual(decoded, original)
    }

    func test_decode_unknownFormatVersion_throwsTypedError() throws {
        var future = sampleExport()
        future.formatVersion = 99
        let data = try CueListTransfer.encode(future)
        XCTAssertThrowsError(try CueListTransfer.decode(data)) { error in
            XCTAssertEqual(error as? CueListTransfer.TransferError, .unsupportedFormatVersion(99))
        }
    }

    func test_decode_nonOCCUData_throwsMalformedPayload() {
        let cuelistBytes = Data("OCUE".utf8) + Data(repeating: 0, count: 40)
        XCTAssertThrowsError(try CueListTransfer.decode(cuelistBytes)) { error in
            XCTAssertEqual(error as? CueListTransfer.TransferError, .malformedPayload)
        }
    }

    func test_decode_garbageJSONInsideEnvelope_throwsMalformedPayload() throws {
        let sealed = try CuelistCrypto.seal(
            Data("not json".utf8),
            magic: CuelistCrypto.cueListExportMagic
        )
        XCTAssertThrowsError(try CueListTransfer.decode(sealed)) { error in
            XCTAssertEqual(error as? CueListTransfer.TransferError, .malformedPayload)
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodegen generate && xcodebuild test -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/CueListTransferTests 2>&1 | xcbeautify`
Expected: compile failure — `CueListExport`, `ExportedSourceMedia`, `CueListTransfer` do not exist.

- [ ] **Step 3: Create `CueListTransfer.swift`**

Create `OnlyCue/Commands/CueListTransfer.swift`:

```swift
import Foundation

/// The decrypted payload of a `.occues` file — one media item's cue list plus
/// the `CuePointType` definitions those cues reference. Schema-independent of
/// `ProjectModel`; versioned by its own `formatVersion`.
struct CueListExport: Codable, Equatable {
    var formatVersion: Int
    var exportedAt: Date
    var sourceMedia: ExportedSourceMedia
    var cuePointTypes: [CuePointType]
    var cues: [Cue]
}

/// Identity of the media a `.occues` file was exported from. Drives the
/// import-time mismatch warning.
struct ExportedSourceMedia: Codable, Equatable {
    var displayName: String
    var duration: TimeInterval
}

/// Encodes/decodes `.occues` files and reconciles an imported cue list into a
/// destination project. Pure logic — no AppKit, no document mutation. The
/// undoable model write lives in `CueCommands.importCueList`.
enum CueListTransfer {

    static let currentFormatVersion = 1

    enum TransferError: Error, Equatable {
        case unsupportedFormatVersion(Int)
        case malformedPayload
    }

    /// Probe used to read `formatVersion` before decoding the whole payload, so
    /// an unknown version surfaces as `.unsupportedFormatVersion` rather than a
    /// generic decode failure.
    private struct FormatProbe: Decodable { let formatVersion: Int }

    // MARK: Codec

    static func encode(_ export: CueListExport) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let json = try encoder.encode(export)
        return try CuelistCrypto.seal(json, magic: CuelistCrypto.cueListExportMagic)
    }

    static func decode(_ data: Data) throws -> CueListExport {
        let json: Data
        do {
            json = try CuelistCrypto.open(
                data,
                magic: CuelistCrypto.cueListExportMagic,
                allowLegacyPlaintext: false
            )
        } catch {
            throw TransferError.malformedPayload
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let probe = try? decoder.decode(FormatProbe.self, from: json) else {
            throw TransferError.malformedPayload
        }
        guard probe.formatVersion == currentFormatVersion else {
            throw TransferError.unsupportedFormatVersion(probe.formatVersion)
        }
        guard let export = try? decoder.decode(CueListExport.self, from: json) else {
            throw TransferError.malformedPayload
        }
        return export
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodegen generate && xcodebuild test -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/CueListTransferTests 2>&1 | xcbeautify`
Expected: PASS — all 4 tests.

- [ ] **Step 5: Commit**

```bash
git add OnlyCue/Commands/CueListTransfer.swift OnlyCueTests/CueListTransferTests.swift
git commit -m "feat(commands): add .occues payload model and codec"
```

---

## Task 3: Export builder + media-match helper

`makeExport` builds a `CueListExport` from a `MediaItem`, carrying only the
`CuePointType`s its cues reference. `mediaMatches` is the import-time identity
check (name equal AND duration within 0.5 s).

**Files:**

- Modify: `OnlyCue/Commands/CueListTransfer.swift`
- Test: `OnlyCueTests/CueListTransferTests.swift`

- [ ] **Step 1: Write the failing tests**

Add these methods inside `final class CueListTransferTests`:

```swift
    private func mediaItem(name: String, duration: TimeInterval, cues: [Cue]) -> MediaItem {
        MediaItem(
            id: UUID(),
            media: MediaReference(
                displayName: name,
                kind: .audio,
                duration: duration,
                bookmarkData: Data([0x00])
            ),
            cues: cues
        )
    }

    func test_makeExport_carriesOnlyReferencedTypes() {
        let usedA = sampleType(name: "Used A")
        let usedB = sampleType(name: "Used B")
        let unused = sampleType(name: "Unused")
        let item = mediaItem(
            name: "song.wav",
            duration: 100,
            cues: [sampleCue(typeID: usedA.id), sampleCue(typeID: usedB.id)]
        )

        let export = CueListTransfer.makeExport(
            of: item,
            projectTypes: [usedA, unused, usedB]
        )

        XCTAssertEqual(export.formatVersion, CueListTransfer.currentFormatVersion)
        XCTAssertEqual(Set(export.cuePointTypes.map(\.id)), [usedA.id, usedB.id])
        XCTAssertEqual(export.cues.count, 2)
        XCTAssertEqual(export.sourceMedia.displayName, "song.wav")
        XCTAssertEqual(export.sourceMedia.duration, 100)
    }

    func test_makeExport_emptyCueList_producesEmptyExport() {
        let item = mediaItem(name: "song.wav", duration: 100, cues: [])
        let export = CueListTransfer.makeExport(of: item, projectTypes: [sampleType()])
        XCTAssertTrue(export.cues.isEmpty)
        XCTAssertTrue(export.cuePointTypes.isEmpty)
    }

    func test_mediaMatches_exactName_andDurationWithinTolerance() {
        let type = sampleType()
        let export = CueListExport(
            formatVersion: 1,
            exportedAt: Date(),
            sourceMedia: ExportedSourceMedia(displayName: "song.wav", duration: 100.0),
            cuePointTypes: [type],
            cues: []
        )
        XCTAssertTrue(CueListTransfer.mediaMatches(
            export, mediaItem(name: "song.wav", duration: 100.4, cues: [])
        ))
        XCTAssertFalse(CueListTransfer.mediaMatches(
            export, mediaItem(name: "song.wav", duration: 101.0, cues: [])
        ))
        XCTAssertFalse(CueListTransfer.mediaMatches(
            export, mediaItem(name: "OTHER.wav", duration: 100.0, cues: [])
        ))
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodegen generate && xcodebuild test -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/CueListTransferTests 2>&1 | xcbeautify`
Expected: compile failure — `makeExport` and `mediaMatches` do not exist.

- [ ] **Step 3: Add `makeExport` and `mediaMatches`**

In `OnlyCue/Commands/CueListTransfer.swift`, add this `// MARK:` section inside the `enum CueListTransfer`, after the `decode` method:

```swift
    // MARK: Export

    /// Build a `.occues` payload from one media item. `cuePointTypes` carries
    /// only the types `item.cues` reference, preserving `projectTypes` order.
    static func makeExport(
        of item: MediaItem,
        projectTypes: [CuePointType],
        now: Date = Date()
    ) -> CueListExport {
        let referencedIDs = Set(item.cues.map(\.typeID))
        return CueListExport(
            formatVersion: currentFormatVersion,
            exportedAt: now,
            sourceMedia: ExportedSourceMedia(
                displayName: item.media.displayName,
                duration: item.media.duration
            ),
            cuePointTypes: projectTypes.filter { referencedIDs.contains($0.id) },
            cues: item.cues
        )
    }

    /// True when `item` is plausibly the same media the export came from:
    /// identical display name and a duration within 0.5 s. Drives the
    /// import-time mismatch confirmation.
    static func mediaMatches(_ export: CueListExport, _ item: MediaItem) -> Bool {
        export.sourceMedia.displayName == item.media.displayName
            && abs(export.sourceMedia.duration - item.media.duration) <= 0.5
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodegen generate && xcodebuild test -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/CueListTransferTests 2>&1 | xcbeautify`
Expected: PASS — all CueListTransferTests (7 total).

- [ ] **Step 5: Commit**

```bash
git add OnlyCue/Commands/CueListTransfer.swift OnlyCueTests/CueListTransferTests.swift
git commit -m "feat(commands): build .occues export payload from a media item"
```

---

## Task 4: Type reconciliation

`reconcileTypes` turns the payload's `CuePointType`s into *new* types for the
destination catalog: fresh ids, `hotkey` dropped to `nil`, names disambiguated
with `(imported)` on collision. Returns the new types plus a
source-id → new-id map.

**Files:**

- Modify: `OnlyCue/Commands/CueListTransfer.swift`
- Test: `OnlyCueTests/CueListTransferTests.swift`

- [ ] **Step 1: Write the failing tests**

Add these methods inside `final class CueListTransferTests`:

```swift
    func test_reconcileTypes_uniqueName_keptAsIs_freshID_hotkeyDropped() {
        let source = sampleType(name: "Haze", hotkey: 5)
        let result = CueListTransfer.reconcileTypes([source], existing: [sampleType(name: "General", hotkey: nil)])

        XCTAssertEqual(result.typesToAdd.count, 1)
        let added = result.typesToAdd[0]
        XCTAssertEqual(added.name, "Haze")
        XCTAssertNotEqual(added.id, source.id, "imported type must get a fresh id")
        XCTAssertNil(added.hotkey, "imported type must not carry a hotkey")
        XCTAssertEqual(added.colorHex, source.colorHex)
        XCTAssertEqual(result.idMap[source.id], added.id)
    }

    func test_reconcileTypes_nameCollision_suffixedImported() {
        let source = sampleType(name: "Spotlight")
        let existing = sampleType(name: "Spotlight")
        let result = CueListTransfer.reconcileTypes([source], existing: [existing])
        XCTAssertEqual(result.typesToAdd[0].name, "Spotlight (imported)")
    }

    func test_reconcileTypes_doubleCollision_numbersTheSuffix() {
        let source = sampleType(name: "Spotlight")
        let existing = [
            sampleType(name: "Spotlight"),
            sampleType(name: "Spotlight (imported)")
        ]
        let result = CueListTransfer.reconcileTypes([source], existing: existing)
        XCTAssertEqual(result.typesToAdd[0].name, "Spotlight (imported 2)")
    }

    func test_reconcileTypes_collisionWithinSameBatch_isDisambiguated() {
        let result = CueListTransfer.reconcileTypes(
            [sampleType(name: "Wash"), sampleType(name: "Wash")],
            existing: []
        )
        XCTAssertEqual(result.typesToAdd.map(\.name), ["Wash", "Wash (imported)"])
    }

    func test_reconcileTypes_nameMatchIsCaseAndWhitespaceInsensitive() {
        let result = CueListTransfer.reconcileTypes(
            [sampleType(name: "spotlight")],
            existing: [sampleType(name: "  Spotlight ")]
        )
        XCTAssertEqual(result.typesToAdd[0].name, "spotlight (imported)")
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodegen generate && xcodebuild test -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/CueListTransferTests 2>&1 | xcbeautify`
Expected: compile failure — `reconcileTypes` does not exist.

- [ ] **Step 3: Add `reconcileTypes`**

In `OnlyCue/Commands/CueListTransfer.swift`, add this `// MARK:` section inside `enum CueListTransfer`, after the `mediaMatches` method:

```swift
    // MARK: Import reconciliation

    /// The result of folding a payload's types into a destination catalog.
    struct TypeReconciliation {
        /// New `CuePointType`s to append to the destination's catalog.
        var typesToAdd: [CuePointType]
        /// Maps each payload type's original id to its new id.
        var idMap: [UUID: UUID]
    }

    /// Reconcile imported types against `existing` — the always-additive rule:
    /// every payload type becomes a brand-new destination type (fresh id,
    /// `hotkey` cleared so it can't hijack a destination digit binding). A name
    /// that collides with `existing` (or with a type added earlier in this same
    /// batch) gets a ` (imported)` / ` (imported 2)` … suffix. The destination's
    /// own catalog is never modified by this function.
    static func reconcileTypes(
        _ payloadTypes: [CuePointType],
        existing: [CuePointType]
    ) -> TypeReconciliation {
        var idMap: [UUID: UUID] = [:]
        var typesToAdd: [CuePointType] = []
        var takenNames = Set(existing.map { normalizedName($0.name) })

        for source in payloadTypes {
            let newID = UUID()
            idMap[source.id] = newID
            var copy = source
            copy.id = newID
            copy.hotkey = nil
            copy.name = uniqueName(source.name, taken: takenNames)
            takenNames.insert(normalizedName(copy.name))
            typesToAdd.append(copy)
        }
        return TypeReconciliation(typesToAdd: typesToAdd, idMap: idMap)
    }

    private static func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func uniqueName(_ base: String, taken: Set<String>) -> String {
        guard taken.contains(normalizedName(base)) else { return base }
        var candidate = "\(base) (imported)"
        var counter = 2
        while taken.contains(normalizedName(candidate)) {
            candidate = "\(base) (imported \(counter))"
            counter += 1
        }
        return candidate
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodegen generate && xcodebuild test -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/CueListTransferTests 2>&1 | xcbeautify`
Expected: PASS — all CueListTransferTests (12 total).

- [ ] **Step 5: Commit**

```bash
git add OnlyCue/Commands/CueListTransfer.swift OnlyCueTests/CueListTransferTests.swift
git commit -m "feat(commands): reconcile imported cue types additively"
```

---

## Task 5: Cue reconciliation

`reconcileCues` gives every imported cue a fresh id and remaps its `typeID`
through the type id-map; every other field is preserved verbatim.

**Files:**

- Modify: `OnlyCue/Commands/CueListTransfer.swift`
- Test: `OnlyCueTests/CueListTransferTests.swift`

- [ ] **Step 1: Write the failing tests**

Add these methods inside `final class CueListTransferTests`:

```swift
    func test_reconcileCues_regeneratesIDs_andRemapsTypeID() {
        let oldTypeID = UUID()
        let newTypeID = UUID()
        let cue = sampleCue(typeID: oldTypeID, number: 1.5)

        let result = CueListTransfer.reconcileCues([cue], idMap: [oldTypeID: newTypeID])

        XCTAssertEqual(result.count, 1)
        XCTAssertNotEqual(result[0].id, cue.id, "imported cue must get a fresh id")
        XCTAssertEqual(result[0].typeID, newTypeID, "typeID must be remapped")
    }

    func test_reconcileCues_preservesEveryOtherField() {
        let oldTypeID = UUID()
        let cue = Cue(
            id: UUID(),
            typeID: oldTypeID,
            cueNumber: 2.5,
            name: "Wash full",
            time: 12.0,
            notes: "hold",
            fadeTime: FadeTime(fadeIn: 1.0, fadeOut: 2.0),
            bpm: 120,
            beatsPerBar: 4
        )
        let result = CueListTransfer.reconcileCues([cue], idMap: [oldTypeID: UUID()])[0]

        XCTAssertEqual(result.cueNumber, 2.5)
        XCTAssertEqual(result.name, "Wash full")
        XCTAssertEqual(result.time, 12.0)
        XCTAssertEqual(result.notes, "hold")
        XCTAssertEqual(result.fadeTime, FadeTime(fadeIn: 1.0, fadeOut: 2.0))
        XCTAssertEqual(result.bpm, 120)
        XCTAssertEqual(result.beatsPerBar, 4)
    }

    func test_reconcileCues_unmappedTypeID_keepsOriginal() {
        // Defensive: a payload cue whose type isn't in the map (hand-tampered
        // file) keeps its original typeID rather than crashing.
        let strayTypeID = UUID()
        let cue = sampleCue(typeID: strayTypeID)
        let result = CueListTransfer.reconcileCues([cue], idMap: [:])[0]
        XCTAssertEqual(result.typeID, strayTypeID)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodegen generate && xcodebuild test -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/CueListTransferTests 2>&1 | xcbeautify`
Expected: compile failure — `reconcileCues` does not exist.

- [ ] **Step 3: Add `reconcileCues`**

In `OnlyCue/Commands/CueListTransfer.swift`, add this method inside `enum CueListTransfer`, immediately after `reconcileTypes` (before the `private` helpers):

```swift
    /// Reconcile imported cues for the destination: a fresh `id` per cue
    /// (uniqueness, including against re-imports) and `typeID` remapped through
    /// `idMap`. `cueNumber`, `time`, `name`, `notes`, `fadeTime`, `bpm` and
    /// `beatsPerBar` are preserved verbatim — a console-facing `cueNumber` is
    /// never silently rewritten. A `typeID` absent from `idMap` is left as-is.
    static func reconcileCues(_ payloadCues: [Cue], idMap: [UUID: UUID]) -> [Cue] {
        payloadCues.map { cue in
            var copy = cue
            copy.id = UUID()
            if let mapped = idMap[cue.typeID] {
                copy.typeID = mapped
            }
            return copy
        }
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodegen generate && xcodebuild test -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/CueListTransferTests 2>&1 | xcbeautify`
Expected: PASS — all CueListTransferTests (15 total).

- [ ] **Step 5: Commit**

```bash
git add OnlyCue/Commands/CueListTransfer.swift OnlyCueTests/CueListTransferTests.swift
git commit -m "feat(commands): reconcile imported cues with fresh ids and remapped types"
```

---

## Task 6: `CueCommands.importCueList` command

The one undoable model write. It needs the cross-boundary undo seam
`mutateProject`, currently `fileprivate` in `CueCommands+Types.swift` — widen it
to `internal` so a sibling file can call it.

**Files:**

- Modify: `OnlyCue/Commands/CueCommands+Types.swift` (one keyword change)
- Create: `OnlyCue/Commands/CueCommands+Transfer.swift`
- Test: `OnlyCueTests/CueCommandsTransferTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `OnlyCueTests/CueCommandsTransferTests.swift`:

```swift
import XCTest
@testable import OnlyCue

@MainActor
final class CueCommandsTransferTests: XCTestCase {

    // MARK: fixtures

    private func makeUndoManager() -> UndoManager {
        let undo = UndoManager()
        undo.groupsByEvent = false
        return undo
    }

    private func makeItem(name: String, cues: [Cue]) -> MediaItem {
        MediaItem(
            id: UUID(),
            media: MediaReference(
                displayName: name,
                kind: .audio,
                duration: 100,
                bookmarkData: Data([0x00])
            ),
            cues: cues
        )
    }

    private func cue(typeID: UUID, time: TimeInterval) -> Cue {
        Cue(
            id: UUID(),
            typeID: typeID,
            cueNumber: 1,
            name: "c",
            time: time,
            notes: "",
            fadeTime: FadeTime(fadeIn: 0, fadeOut: 0)
        )
    }

    /// A document with one active item that has no cues.
    private func documentWithEmptyActiveItem() -> CueListDocument {
        let doc = CueListDocument()
        let item = makeItem(name: "song.wav", cues: [])
        CueCommands.addItem(item, to: doc, undoManager: nil)
        return doc
    }

    private func export(typeName: String, cueTimes: [TimeInterval]) -> CueListExport {
        let typeID = UUID()
        return CueListExport(
            formatVersion: CueListTransfer.currentFormatVersion,
            exportedAt: Date(),
            sourceMedia: ExportedSourceMedia(displayName: "song.wav", duration: 100),
            cuePointTypes: [CuePointType(id: typeID, name: typeName, colorHex: "#FFFFFF")],
            cues: cueTimes.map { cue(typeID: typeID, time: $0) }
        )
    }

    // MARK: tests

    func test_importCueList_replace_setsCuesAndAddsType() {
        let doc = documentWithEmptyActiveItem()
        let typesBefore = doc.model.cuePointTypes.count

        CueCommands.importCueList(
            export(typeName: "Haze", cueTimes: [1, 2, 3]),
            mode: .replace,
            document: doc,
            undoManager: nil
        )

        XCTAssertEqual(doc.model.items[0].cues.map(\.time), [1, 2, 3])
        XCTAssertEqual(doc.model.cuePointTypes.count, typesBefore + 1)
        // Imported cues point at the newly-added type.
        let newTypeID = doc.model.cuePointTypes.last!.id
        XCTAssertTrue(doc.model.items[0].cues.allSatisfy { $0.typeID == newTypeID })
    }

    func test_importCueList_add_appendsToExistingCues() {
        let doc = CueListDocument()
        let existingType = doc.model.cuePointTypes[0].id
        let item = makeItem(name: "song.wav", cues: [cue(typeID: existingType, time: 9)])
        CueCommands.addItem(item, to: doc, undoManager: nil)

        CueCommands.importCueList(
            export(typeName: "Haze", cueTimes: [1, 2]),
            mode: .add,
            document: doc,
            undoManager: nil
        )

        XCTAssertEqual(doc.model.items[0].cues.map(\.time), [9, 1, 2])
    }

    func test_importCueList_undo_restoresCuesAndTypes() {
        let doc = documentWithEmptyActiveItem()
        let typesBefore = doc.model.cuePointTypes
        let undo = makeUndoManager()

        CueCommands.importCueList(
            export(typeName: "Haze", cueTimes: [1, 2, 3]),
            mode: .replace,
            document: doc,
            undoManager: undo
        )
        XCTAssertEqual(doc.model.items[0].cues.count, 3)

        undo.undo()
        XCTAssertTrue(doc.model.items[0].cues.isEmpty)
        XCTAssertEqual(doc.model.cuePointTypes, typesBefore)

        undo.redo()
        XCTAssertEqual(doc.model.items[0].cues.count, 3)
        XCTAssertEqual(doc.model.cuePointTypes.count, typesBefore.count + 1)
    }

    func test_importCueList_noActiveItem_isNoOp() {
        let doc = CueListDocument() // no items, no active item
        CueCommands.importCueList(
            export(typeName: "Haze", cueTimes: [1]),
            mode: .replace,
            document: doc,
            undoManager: nil
        )
        XCTAssertTrue(doc.model.items.isEmpty)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodegen generate && xcodebuild test -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/CueCommandsTransferTests 2>&1 | xcbeautify`
Expected: compile failure — `CueCommands.importCueList` does not exist.

- [ ] **Step 3: Widen `mutateProject` to `internal`**

In `OnlyCue/Commands/CueCommands+Types.swift`, find this line:

```swift
    fileprivate static func mutateProject(
```

Change it to:

```swift
    static func mutateProject(
```

(Leave `restoreProject` and `ProjectSnapshot` as `fileprivate` — they are only used within `CueCommands+Types.swift`.)

- [ ] **Step 4: Create `CueCommands+Transfer.swift`**

Create `OnlyCue/Commands/CueCommands+Transfer.swift`:

```swift
import Foundation

@MainActor
extension CueCommands {

    /// How an imported cue list combines with the active item's existing cues.
    enum CueImportMode {
        case replace
        case add
    }

    /// Apply a decoded `.occues` payload to the document's active media item.
    /// Reconciles the payload's types additively into the catalog, remaps the
    /// imported cues onto the new types, and writes both in a single undo group
    /// ("Import Cue List"). No-op when there is no active item.
    static func importCueList(
        _ export: CueListExport,
        mode: CueImportMode,
        document: CueListDocument,
        undoManager: UndoManager?
    ) {
        guard let activeID = document.model.activeItemID,
              let itemIndex = document.model.items.firstIndex(where: { $0.id == activeID })
        else { return }

        let reconciliation = CueListTransfer.reconcileTypes(
            export.cuePointTypes,
            existing: document.model.cuePointTypes
        )
        let importedCues = CueListTransfer.reconcileCues(
            export.cues,
            idMap: reconciliation.idMap
        )

        mutateProject(document, undoManager: undoManager, actionName: "Import Cue List") { model in
            model.cuePointTypes.append(contentsOf: reconciliation.typesToAdd)
            switch mode {
            case .replace:
                model.items[itemIndex].cues = importedCues
            case .add:
                model.items[itemIndex].cues.append(contentsOf: importedCues)
            }
        }
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodegen generate && xcodebuild test -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/CueCommandsTransferTests 2>&1 | xcbeautify`
Expected: PASS — all 4 tests.

- [ ] **Step 6: Commit**

```bash
git add OnlyCue/Commands/CueCommands+Types.swift OnlyCue/Commands/CueCommands+Transfer.swift OnlyCueTests/CueCommandsTransferTests.swift
git commit -m "feat(commands): add undoable importCueList command"
```

---

## Task 7: Register the `.occues` UTType

Declare `com.onlycue.cues` in `Info.plist` and expose `UTType.cueListExport` so
the open/save panels can filter to it.

**Files:**

- Modify: `OnlyCue/Resources/Info.plist`
- Modify: `OnlyCue/Document/CueListDocument.swift`
- Test: `OnlyCueTests/CueListTransferTests.swift`

- [ ] **Step 1: Write the failing test**

Add this method inside `final class CueListTransferTests` (add `import UniformTypeIdentifiers` to the file's imports if not already present):

```swift
    func test_cueListExportUTType_hasExpectedIdentifierAndExtension() {
        XCTAssertEqual(UTType.cueListExport.identifier, "com.onlycue.cues")
        XCTAssertTrue(
            UTType.cueListExport.tags[.filenameExtension]?.contains("occues") ?? false,
            "the cueListExport UTType must own the .occues extension"
        )
    }
```

At the top of `OnlyCueTests/CueListTransferTests.swift`, ensure the imports read:

```swift
import XCTest
import UniformTypeIdentifiers
@testable import OnlyCue
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodegen generate && xcodebuild test -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/CueListTransferTests/test_cueListExportUTType_hasExpectedIdentifierAndExtension 2>&1 | xcbeautify`
Expected: compile failure — `UTType.cueListExport` does not exist.

- [ ] **Step 3: Add the UTType declaration to `Info.plist`**

In `OnlyCue/Resources/Info.plist`, the `UTExportedTypeDeclarations` array currently
holds one `<dict>` (for `com.onlycue.cuelist`). Add a second `<dict>` as a sibling
immediately after the first one's closing `</dict>`, so the array reads:

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
        <dict>
            <key>UTTypeConformsTo</key>
            <array>
                <string>public.data</string>
            </array>
            <key>UTTypeDescription</key>
            <string>OnlyCue Cue List</string>
            <key>UTTypeIdentifier</key>
            <string>com.onlycue.cues</string>
            <key>UTTypeTagSpecification</key>
            <dict>
                <key>public.filename-extension</key>
                <array>
                    <string>occues</string>
                </array>
            </dict>
        </dict>
    </array>
```

- [ ] **Step 4: Add `UTType.cueListExport`**

In `OnlyCue/Document/CueListDocument.swift`, the file begins with:

```swift
extension UTType {
    static let cueList = UTType(exportedAs: "com.onlycue.cuelist")
}
```

Change that extension to:

```swift
extension UTType {
    static let cueList = UTType(exportedAs: "com.onlycue.cuelist")
    /// The portable `.occues` cue-list interchange file (not a document type —
    /// handled via NSOpenPanel/NSSavePanel, never DocumentGroup).
    static let cueListExport = UTType(exportedAs: "com.onlycue.cues")
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `xcodegen generate && xcodebuild test -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/CueListTransferTests 2>&1 | xcbeautify`
Expected: PASS — all CueListTransferTests (16 total).

- [ ] **Step 6: Commit**

```bash
git add OnlyCue/Resources/Info.plist OnlyCue/Document/CueListDocument.swift OnlyCueTests/CueListTransferTests.swift
git commit -m "feat(document): register the .occues exported UTType"
```

---

## Task 8: `CueTransferAction` — AppKit panels & alerts

The thin AppKit glue: save/open panels, the mismatch confirmation, the
Replace/Add/Cancel conflict dialog, and error reporting. Mirrors
`OnlyCue/Document/TemplateAction.swift`. No unit tests — modal AppKit panels are
not unit-testable; all logic it relies on is already tested in
`CueListTransfer` / `CueCommands`. Verified by a build and by the Task 10 UITest.

**Files:**

- Create: `OnlyCue/UI/CueTransferAction.swift`

- [ ] **Step 1: Create `CueTransferAction.swift`**

Create `OnlyCue/UI/CueTransferAction.swift`:

```swift
import AppKit
import UniformTypeIdentifiers

/// Wires the Cue menu's Export / Import Cue List actions to the `.occues`
/// interchange format. Holds the AppKit-side concerns — `NSSavePanel`,
/// `NSOpenPanel`, and the mismatch / conflict `NSAlert`s — out of the SwiftUI
/// body. Same pattern as `TemplateAction`. Pure transfer logic lives in
/// `CueListTransfer`; the undoable model write is `CueCommands.importCueList`.
enum CueTransferAction {

    /// Export the active item's cue list to a user-chosen `.occues` file.
    /// No-op when there is no active item or the user cancels the panel.
    @MainActor
    static func export(from document: CueListDocument) {
        guard let item = document.model.activeItem else { return }
        let export = CueListTransfer.makeExport(
            of: item,
            projectTypes: document.model.cuePointTypes
        )

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.cueListExport]
        panel.nameFieldStringValue = "\(item.resolvedName) cues.occues"
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try CueListTransfer.encode(export).write(to: url)
        } catch {
            presentError(message: "The cue list could not be exported.")
        }
    }

    /// Import a `.occues` file onto the active item. Runs the mismatch check and
    /// the conflict dialog, then delegates to `CueCommands.importCueList`.
    /// No-op when there is no active item or the user cancels.
    @MainActor
    static func `import`(into document: CueListDocument, undoManager: UndoManager?) {
        guard let item = document.model.activeItem else { return }

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.cueListExport]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let export: CueListExport
        do {
            export = try CueListTransfer.decode(try Data(contentsOf: url))
        } catch let error as CueListTransfer.TransferError {
            presentError(message: message(for: error))
            return
        } catch {
            presentError(message: "The cue list file could not be read.")
            return
        }

        if !CueListTransfer.mediaMatches(export, item),
           !confirmMismatch(export: export, item: item) {
            return
        }

        let mode: CueCommands.CueImportMode
        if item.cues.isEmpty {
            mode = .replace
        } else {
            switch conflictChoice() {
            case .some(true): mode = .replace
            case .some(false): mode = .add
            case .none: return // cancelled
            }
        }

        CueCommands.importCueList(export, mode: mode, document: document, undoManager: undoManager)
    }

    // MARK: - Alerts

    /// Mismatch confirmation. Returns true to proceed with the import.
    @MainActor
    private static func confirmMismatch(export: CueListExport, item: MediaItem) -> Bool {
        let alert = NSAlert()
        alert.messageText = "This cue list is from a different song"
        alert.informativeText = """
        The cue list was exported from “\(export.sourceMedia.displayName)” \
        (\(formatted(export.sourceMedia.duration))). The selected song is \
        “\(item.resolvedName)” (\(formatted(item.media.duration))).

        Import the cues anyway?
        """
        alert.addButton(withTitle: "Import")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Conflict dialog for a non-empty target. Returns `true` for Replace,
    /// `false` for Add, `nil` for Cancel.
    @MainActor
    private static func conflictChoice() -> Bool? {
        let alert = NSAlert()
        alert.messageText = "This song already has cues"
        alert.informativeText = "Replace the existing cues with the imported ones, or add the imported cues alongside them?"
        alert.addButton(withTitle: "Replace")  // .alertFirstButtonReturn
        alert.addButton(withTitle: "Add")      // .alertSecondButtonReturn
        alert.addButton(withTitle: "Cancel")   // .alertThirdButtonReturn
        switch alert.runModal() {
        case .alertFirstButtonReturn: return true
        case .alertSecondButtonReturn: return false
        default: return nil
        }
    }

    @MainActor
    private static func presentError(message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Cue List Import Failed"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private static func message(for error: CueListTransfer.TransferError) -> String {
        switch error {
        case .unsupportedFormatVersion:
            return "This cue list was created by a newer version of OnlyCue and can't be opened."
        case .malformedPayload:
            return "The file is not a valid OnlyCue cue list."
        }
    }

    /// `m:ss` rendering of a media duration for the mismatch alert.
    private static func formatted(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
```

- [ ] **Step 2: Verify the project builds**

Run: `xcodegen generate && xcodebuild build -project OnlyCue.xcodeproj -scheme OnlyCue -configuration Debug -destination 'platform=macOS' 2>&1 | xcbeautify`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add OnlyCue/UI/CueTransferAction.swift
git commit -m "feat(ui): add .occues export/import panels and dialogs"
```

---

## Task 9: Cue-menu items + notification wiring

Add the two menu items, define their notifications, and route them through a
`ViewModifier` — mirroring `TemplateMenuReceiver`.

**Files:**

- Modify: `OnlyCue/UI/DocumentView.swift` (notification names + apply modifier)
- Create: `OnlyCue/UI/CueTransferMenuReceiver.swift`
- Modify: `OnlyCue/App/AppCommands.swift` (Cue-menu items)

- [ ] **Step 1: Add the notification names**

In `OnlyCue/UI/DocumentView.swift`, find the `extension Notification.Name` block
(it starts with `static let importMediaRequested = …`). Add these two lines at
the end of that extension, before its closing brace:

```swift
    static let exportCueListRequested = Notification.Name("OnlyCue.exportCueListRequested")
    static let importCueListRequested = Notification.Name("OnlyCue.importCueListRequested")
```

- [ ] **Step 2: Create `CueTransferMenuReceiver.swift`**

Create `OnlyCue/UI/CueTransferMenuReceiver.swift`:

```swift
import SwiftUI

/// View modifier that listens for `.exportCueListRequested` and
/// `.importCueListRequested` and routes them to `CueTransferAction`. Extracted
/// from `DocumentView` so the handlers stay close together and the view stays
/// under SwiftLint's `type_body_length` cap. Same pattern as
/// `TemplateMenuReceiver`.
struct CueTransferMenuReceiver: ViewModifier {

    @ObservedObject var document: CueListDocument
    var undoManager: UndoManager?

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .exportCueListRequested)) { _ in
                CueTransferAction.export(from: document)
            }
            .onReceive(NotificationCenter.default.publisher(for: .importCueListRequested)) { _ in
                CueTransferAction.import(into: document, undoManager: undoManager)
            }
    }
}

extension View {
    func cueTransferMenuReceiver(
        document: CueListDocument,
        undoManager: UndoManager?
    ) -> some View {
        modifier(CueTransferMenuReceiver(document: document, undoManager: undoManager))
    }
}
```

- [ ] **Step 3: Apply the modifier in `DocumentView`**

In `OnlyCue/UI/DocumentView.swift`, find the existing `.templateMenuReceiver(...)`
call:

```swift
        .templateMenuReceiver(
            document: document,
            pendingErrorMessage: pendingAlertMessageBinding,
            undoManager: undoManager
        )
```

Add the new modifier immediately after it:

```swift
        .templateMenuReceiver(
            document: document,
            pendingErrorMessage: pendingAlertMessageBinding,
            undoManager: undoManager
        )
        .cueTransferMenuReceiver(document: document, undoManager: undoManager)
```

- [ ] **Step 4: Add the Cue-menu items**

In `OnlyCue/App/AppCommands.swift`, find the `CommandMenu("Cue")` block. It ends
with the `Button("Snap to Nearest Bar")` item. Add a `Divider()` and two buttons
just before the `CommandMenu("Cue")` closing brace, so the tail of that menu reads:

```swift
            Button("Snap to Nearest Bar") {
                NotificationCenter.default.post(name: .snapSelectedCuesToBar, object: nil)
            }
            .keyboardShortcut(shortcut(.snapSelectedCuesToBar))

            Divider()

            Button {
                NotificationCenter.default.post(name: .exportCueListRequested, object: nil)
            } label: {
                Label("Export Cue List…", systemImage: "square.and.arrow.up.on.square")
            }
            .accessibilityIdentifier("exportCueListMenuItem")

            Button {
                NotificationCenter.default.post(name: .importCueListRequested, object: nil)
            } label: {
                Label("Import Cue List…", systemImage: "square.and.arrow.down.on.square")
            }
            .accessibilityIdentifier("importCueListMenuItem")
        }
```

(The existing File-menu item labelled "Export Cues…" is the unrelated CSV export
— `.exportCuesToCSVRequested`. Our two items are "Export/Import Cue **List**…"
and live in the Cue menu; do not merge or rename the CSV item.)

- [ ] **Step 5: Verify the project builds**

Run: `xcodegen generate && xcodebuild build -project OnlyCue.xcodeproj -scheme OnlyCue -configuration Debug -destination 'platform=macOS' 2>&1 | xcbeautify`
Expected: BUILD SUCCEEDED.

- [ ] **Step 6: Commit**

```bash
git add OnlyCue/UI/DocumentView.swift OnlyCue/UI/CueTransferMenuReceiver.swift OnlyCue/App/AppCommands.swift
git commit -m "feat(ui): add Export/Import Cue List to the Cue menu"
```

---

## Task 10: UITest — Cue-menu items present

A focused, non-flaky BDD UITest: the Cue menu exposes both commands. The
`.occues` round-trip itself is fully covered by the unit tests in Tasks 2–6; a
panel-driven round-trip UITest is omitted because macOS system file panels
(`NSOpenPanel` / `NSSavePanel`) cannot be driven reliably from XCUITest.

**Files:**

- Create: `OnlyCueUITests/CueTransferMenuUITests.swift`

- [ ] **Step 1: Write the test**

Create `OnlyCueUITests/CueTransferMenuUITests.swift`:

```swift
import XCTest

/// Given OnlyCue is running, When the user opens the Cue menu, Then it offers
/// Export Cue List… and Import Cue List….
final class CueTransferMenuUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    func test_cueMenu_offersExportAndImportCueList() {
        let app = XCUIApplication()
        app.launch()

        let cueMenu = app.menuBars.menuBarItems["Cue"]
        XCTAssertTrue(cueMenu.waitForExistence(timeout: 10), "Cue menu should exist")
        cueMenu.click()

        XCTAssertTrue(
            app.menuItems["Export Cue List…"].waitForExistence(timeout: 5),
            "Cue menu should contain Export Cue List…"
        )
        XCTAssertTrue(
            app.menuItems["Import Cue List…"].exists,
            "Cue menu should contain Import Cue List…"
        )
    }
}
```

- [ ] **Step 2: Run the test to verify it passes**

Run: `xcodegen generate && xcodebuild test -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueUITests/CueTransferMenuUITests 2>&1 | xcbeautify`
Expected: PASS. (If the menu-item titles fail to match, confirm the `…` is the
single-character ellipsis `U+2026`, matching the `Button` labels in Task 9.)

- [ ] **Step 3: Commit**

```bash
git add OnlyCueUITests/CueTransferMenuUITests.swift
git commit -m "test(ui): verify Export/Import Cue List menu items exist"
```

---

## Task 11: Documentation — ADR + data-model

Record the new format as an ADR and document the `.occues` file in the data
model. Per the OnlyCue CLAUDE.md, docs commits are separate from feature commits.

**Files:**

- Modify: `docs/decisions.md`
- Modify: `docs/data-model.md`

- [ ] **Step 1: Add the ADR**

In `docs/decisions.md`, insert this new ADR immediately below the
`# Architecture Decision Records` header and the ADR-template block, **above**
`## ADR-024` (newest entries on top). Use the next free number after the highest
existing ADR (ADR-024 today → this becomes **ADR-025**; if a higher ADR exists
when you run this, use the next number after that instead):

```markdown
## ADR-025 — Portable cue lists: a `.occues` interchange file, decoupled from the document model

**Date**: 2026-05-22
**Status**: Accepted
**Decision**: A song's cue list can be exported to a portable `.occues` file and imported onto a song in another project. `.occues` reuses the `.cuelist` encrypted envelope (AES-256-GCM, fixed key — ADR-021) with a distinct `OCCU` magic and its own JSON payload carrying `formatVersion`, `sourceMedia`, the referenced `cuePointTypes`, and the `cues`. Import is **always additive for types** — every payload `CuePointType` becomes a new destination type (fresh id, `hotkey` cleared, name suffixed ` (imported)` on collision); the destination catalog is never mutated in place. Imported cues get fresh ids and remapped `typeID`s; `cueNumber` is preserved verbatim. The whole import is one undo group via `CueCommands.importCueList`.
**Why**: Lighting designers reuse the same song across many shows and want prior cue work as a starting point. A standalone interchange file keeps `ProjectModel` unchanged — `data-model.md`'s "no shared cue lists in the model" non-goal still holds — and makes the feature a pure copy-in/copy-out with no cross-project references, no schema bump, and no live-sync surface. Additive type reconciliation avoids ever recoloring or rebinding the destination project's own palette.
**Reversal cost**: Low. `.occues` is an additive, external format with its own `formatVersion`; `CueListTransfer` and `CueCommands+Transfer` are self-contained, and the only shared-code change is parameterizing `CuelistCrypto` by magic (the `.cuelist` path keeps the `OCUE` default).
**Deferred**: carrying tempo maps / lyrics in `.occues`; auto-matching the import to a media item by identity; a global cue library.
```

- [ ] **Step 2: Document `.occues` in the data model**

In `docs/data-model.md`, find the `## What's deliberately NOT in the model`
section. Immediately **above** that section, add:

```markdown
## `.occues` interchange file

A `.occues` file is a portable, one-song cue list — used to copy a marked-up
song's cues from one project into another as a starting point (ADR-025). It is
**not** part of `ProjectModel` and does **not** affect `schemaVersion`: it is an
external artifact produced by `Cue ▸ Export Cue List…` and consumed by
`Cue ▸ Import Cue List…`.

It uses the same encrypted envelope as `.cuelist` (ADR-021) with a distinct
`OCCU` magic. The decrypted payload is JSON with its own `formatVersion`
(currently `1`, independent of `schemaVersion`): `exportedAt`, a `sourceMedia`
identity (`displayName` + `duration`), the referenced `cuePointTypes`, and the
`cues`. On import, types are reconciled additively (new ids, `hotkey` dropped,
` (imported)` suffix on a name collision) and cues get fresh ids with remapped
`typeID`s; `cueNumber` is preserved. UTType `com.onlycue.cues`.

```

(Note the `cross-item cue references or shared cue lists` line in the
"deliberately NOT" list stays — `.occues` is an external file, not a model
feature, so that non-goal is unchanged.)

- [ ] **Step 3: Commit**

```bash
git add docs/decisions.md docs/data-model.md
git commit -m "docs: record ADR-025 portable cue lists (.occues)"
```

---

## Final verification

After all tasks, run the full suites once and confirm green:

```bash
xcodegen generate && xcodebuild test \
  -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS' \
  -only-testing:OnlyCueTests/CuelistCryptoTests \
  -only-testing:OnlyCueTests/CueListTransferTests \
  -only-testing:OnlyCueTests/CueCommandsTransferTests \
  -only-testing:OnlyCueUITests/CueTransferMenuUITests 2>&1 | xcbeautify
```

Then confirm SwiftLint is clean (CI runs `swiftlint lint --strict`):

```bash
swiftlint lint --strict 2>&1 | tail -5
```

Expected: all tests pass; no SwiftLint violations.

---

## Self-review notes (for the plan author / reviewer)

- **Spec coverage:** file format → Tasks 1, 2, 7; export → Tasks 3, 8, 9;
  import + mismatch + conflict → Tasks 5, 6, 8, 9; type reconciliation → Task 4;
  cue reconciliation → Task 5; command/undo → Task 6; UI placement → Task 9;
  edge cases → covered by tests across Tasks 2–6; testing → Tasks 1–6, 10; docs
  → Task 11.
- **Deliberate deviation from the spec:** the spec listed four panel-driven BDD
  UITests. Tasks 10 keeps only the menu-presence UITest, because
  `NSOpenPanel`/`NSSavePanel` are system dialogs XCUITest cannot drive reliably.
  The export→import→reconcile→undo behavior is instead covered comprehensively
  by unit tests (Tasks 2–6). Flag this to the user at review time.
- **Deliberate deviation:** the spec said the menu items are "disabled when no
  active item." `AppCommands` is app-global and cannot observe a focused
  document's `activeItem` (the same reason the existing Cue-menu items are not
  disabled). Instead `CueTransferAction.export`/`import` and
  `CueCommands.importCueList` each guard `activeItem` and no-op when nil —
  matching `TemplateAction`'s precedent.

```
