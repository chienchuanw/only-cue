import SwiftUI
import XCTest
@testable import OnlyCue

/// Headless render check for `MiniPlayerView` (macOS, #748) using `ImageRenderer`
/// — no window/panel plumbing or XCUITest needed. Writes PNGs to the runner's
/// tmp screenshots dir for the Figma↔app review, and asserts each state renders
/// at the expected width. `DS` tokens resolve dark in every appearance
/// (ADR-029), so the output is dark regardless of the renderer's environment.
final class MiniPlayerViewScreenshotTests: XCTestCase {

    private let amberID = UUID()
    private let tealID = UUID()
    // Cool types exist to mirror the Figma density stress case (#773), where a
    // blue/violet tick sits on the indigo fill — the trade-off decision 7 takes.
    private let blueID = UUID()
    private let violetID = UUID()

    private static let clipDuration: TimeInterval = 120

    private func types() -> [CuePointType] {
        [
            CuePointType(id: amberID, name: "Amber", colorHex: "#FFA94D"),
            CuePointType(id: tealID, name: "Teal", colorHex: "#4ECDC4"),
            CuePointType(id: blueID, name: "Blue", colorHex: "#4D96FF"),
            CuePointType(id: violetID, name: "Violet", colorHex: "#9D7EE0")
        ]
    }

    private func item(cues: [Cue]) -> MediaItem {
        MediaItem(
            id: UUID(),
            media: MediaReference(
                displayName: "Dialogue — Scene 2.wav",
                kind: .audio,
                duration: Self.clipDuration,
                bookmarkData: Data([0x00])
            ),
            cues: cues
        )
    }

    private func cue(_ number: Double, _ name: String, _ time: TimeInterval, _ typeID: UUID) -> Cue {
        Cue(id: UUID(), typeID: typeID, cueNumber: number, name: name, time: time, notes: "", fadeTime: .zero)
    }

    private func populatedItem() -> MediaItem {
        item(cues: [
            cue(2, "Verse 1", 30, tealID),
            cue(3, "Chorus Hit", 60, amberID)
        ])
    }

    /// The density stress case: a busy 12-second stretch straddling the playhead
    /// plus sparse cues either side. At ~2pt per second the cluster is meant to
    /// read as a solid block — that is the message, not a rendering failure.
    private func denseItem() -> MediaItem {
        let palette = [amberID, tealID, blueID, violetID]
        let cluster = (0..<9).map { index in
            cue(Double(index) + 3, "Hit \(index + 1)", 40 + Double(index) * 1.5, palette[index % palette.count])
        }
        return item(cues: [cue(1, "Lights Up", 5, amberID), cue(2, "Build", 18, blueID)]
            + cluster
            + [cue(12, "Break", 70, violetID), cue(13, "Final", 95, tealID), cue(14, "Blackout", 110, amberID)])
    }

    private func model(editorMode: EditorMode, item: MediaItem?) -> MiniPlayerModel {
        MiniPlayerModel.make(
            currentTime: 45,
            duration: item == nil ? 0 : Self.clipDuration,
            item: item,
            timecodeSettings: ProjectTimecodeSettings(framerate: .fps30drop),
            cuePointTypes: types(),
            editorMode: editorMode
        )
    }

    private struct RenderCase {
        let name: String
        let model: MiniPlayerModel
        let playing: Bool
        /// Cue markers the progress bar must draw (#773). Guards against a
        /// silently empty tick layer — e.g. a lost `duration` — which would
        /// still render a perfectly valid-looking bar.
        var expectedMarkers: Int = 0
    }

    @MainActor
    func test_render_cueShowEmptyStates() throws {
        let cases = [
            RenderCase(
                name: "miniplayer-cue-dark",
                model: model(editorMode: .cue, item: populatedItem()),
                playing: true,
                expectedMarkers: 2
            ),
            RenderCase(
                name: "miniplayer-show-dark",
                model: model(editorMode: .show, item: populatedItem()),
                playing: true,
                expectedMarkers: 2
            ),
            RenderCase(name: "miniplayer-empty-dark", model: model(editorMode: .cue, item: nil), playing: false),
            RenderCase(
                name: "miniplayer-dense-dark",
                model: model(editorMode: .cue, item: denseItem()),
                playing: true,
                expectedMarkers: 14
            )
        ]

        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("screenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        for testCase in cases {
            XCTAssertEqual(testCase.model.cueMarkers.count, testCase.expectedMarkers, "\(testCase.name) markers")
            let view = MiniPlayerView(model: testCase.model, isPlaying: testCase.playing)
                .frame(width: 620)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2

            guard let image = renderer.nsImage else {
                return XCTFail("ImageRenderer produced no image for \(testCase.name)")
            }
            XCTAssertEqual(image.size.width, 620, accuracy: 1, "\(testCase.name) width")
            XCTAssertGreaterThan(image.size.height, 40, "\(testCase.name) height")

            guard let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else {
                return XCTFail("could not encode PNG for \(testCase.name)")
            }
            let url = dir.appendingPathComponent("\(testCase.name).png")
            try png.write(to: url)
            print("[screenshot] wrote \(url.path)")
        }
    }
}
