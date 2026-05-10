import XCTest
@testable import OnlyCue

/// Golden-file regression tests pinning the byte-equivalent output of every
/// `ExportTarget` against a curated 3-cue fixture. If any future refactor
/// changes the schema or escape behavior, these tests fail loudly with a
/// readable diff so the change is intentional, not silent.
///
/// The "golden file" is inlined as a Swift multi-line string rather than a
/// `.csv` resource on disk — easier to diff in code review, no test-bundle
/// resource plumbing, no editor-converts-tabs-to-spaces footguns. The trade
/// is that test failures show the diff inline rather than as a file diff.
final class CueExportGoldenFileTests: XCTestCase {

    func test_csv_goldenOutput() throws {
        let output = ExportTarget.csv.format(
            cues: try Self.fixture(),
            typeNamesByID: Self.typeNames
        )
        XCTAssertEqual(output, """
        id,name,time,fadeIn,fadeOut,type,notes
        00000000-0000-0000-0000-000000000001,Open,0.0,0.0,0.0,Lighting,
        00000000-0000-0000-0000-000000000002,Bridge,12.5,0.5,1.25,Lighting,key change
        00000000-0000-0000-0000-000000000003,FX hit,30.0,0.0,0.0,Sound,"watch the cue, it's tight"

        """)
    }

    func test_tsv_goldenOutput() throws {
        let output = ExportTarget.tsv.format(
            cues: try Self.fixture(),
            typeNamesByID: Self.typeNames
        )
        // Comma in notes pass through unescaped in TSV.
        XCTAssertEqual(output, """
        id\tname\ttime\tfadeIn\tfadeOut\ttype\tnotes
        00000000-0000-0000-0000-000000000001\tOpen\t0.0\t0.0\t0.0\tLighting\t
        00000000-0000-0000-0000-000000000002\tBridge\t12.5\t0.5\t1.25\tLighting\tkey change
        00000000-0000-0000-0000-000000000003\tFX hit\t30.0\t0.0\t0.0\tSound\twatch the cue, it's tight

        """)
    }

    func test_ma3_goldenOutput() throws {
        let output = ExportTarget.ma3.format(
            cues: try Self.fixture(),
            typeNamesByID: Self.typeNames
        )
        XCTAssertEqual(output, """
        Cue,Name,Trig Time,Fade In,Fade Out,Type,Note
        00000000-0000-0000-0000-000000000001,Open,0.0,0.0,0.0,Lighting,
        00000000-0000-0000-0000-000000000002,Bridge,12.5,0.5,1.25,Lighting,key change
        00000000-0000-0000-0000-000000000003,FX hit,30.0,0.0,0.0,Sound,"watch the cue, it's tight"

        """)
    }

    func test_ma2_goldenOutput_matchesMA3() throws {
        // MA3 and MA2 share the same column convention — they differ only in
        // which console accepts the import. The test pins the equivalence so
        // a future divergence (if MA2 grows its own column layout) breaks
        // here visibly rather than silently.
        let cues = try Self.fixture()
        let ma3 = ExportTarget.ma3.format(cues: cues, typeNamesByID: Self.typeNames)
        let ma2 = ExportTarget.ma2.format(cues: cues, typeNamesByID: Self.typeNames)
        XCTAssertEqual(ma3, ma2)
    }

    // MARK: - Fixture

    private static let lightingID = UUID(uuidString: "00000000-0000-0000-0000-00000000aaaa")
    private static let soundID = UUID(uuidString: "00000000-0000-0000-0000-00000000bbbb")

    private static var typeNames: [UUID: String] {
        var dict: [UUID: String] = [:]
        if let lighting = lightingID { dict[lighting] = "Lighting" }
        if let sound = soundID { dict[sound] = "Sound" }
        return dict
    }

    private static func fixture() throws -> [Cue] {
        let lighting = try XCTUnwrap(lightingID)
        let sound = try XCTUnwrap(soundID)
        return [
            try makeCue(
                idString: "00000000-0000-0000-0000-000000000001",
                typeID: lighting,
                name: "Open",
                time: 0.0,
                notes: ""
            ),
            try makeCue(
                idString: "00000000-0000-0000-0000-000000000002",
                typeID: lighting,
                name: "Bridge",
                time: 12.5,
                notes: "key change",
                fade: FadeTime(fadeIn: 0.5, fadeOut: 1.25)
            ),
            try makeCue(
                idString: "00000000-0000-0000-0000-000000000003",
                typeID: sound,
                name: "FX hit",
                time: 30.0,
                notes: "watch the cue, it's tight"
            )
        ]
    }

    private static func makeCue(
        idString: String,
        typeID: UUID,
        name: String,
        time: TimeInterval,
        notes: String,
        fade: FadeTime = FadeTime(fadeIn: 0, fadeOut: 0)
    ) throws -> Cue {
        Cue(
            id: try XCTUnwrap(UUID(uuidString: idString)),
            typeID: typeID,
            cueNumber: 1,
            name: name,
            time: time,
            notes: notes,
            fadeTime: fade
        )
    }
}
