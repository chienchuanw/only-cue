import XCTest
import UniformTypeIdentifiers
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

    // MARK: codec

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

    // MARK: export builder

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

    // MARK: type reconciliation

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
}
