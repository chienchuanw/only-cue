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
}
