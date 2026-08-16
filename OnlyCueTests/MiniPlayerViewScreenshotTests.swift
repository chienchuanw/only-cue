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

    private func types() -> [CuePointType] {
        [
            CuePointType(id: amberID, name: "Amber", colorHex: "#FFA94D"),
            CuePointType(id: tealID, name: "Teal", colorHex: "#4ECDC4")
        ]
    }

    private func populatedItem() -> MediaItem {
        MediaItem(
            id: UUID(),
            media: MediaReference(
                displayName: "Dialogue — Scene 2.wav",
                kind: .audio,
                duration: 120,
                bookmarkData: Data([0x00])
            ),
            cues: [
                Cue(id: UUID(), typeID: tealID, cueNumber: 2, name: "Verse 1", time: 30, notes: "", fadeTime: .zero),
                Cue(id: UUID(), typeID: amberID, cueNumber: 3, name: "Chorus Hit", time: 60, notes: "", fadeTime: .zero)
            ]
        )
    }

    private func model(editorMode: EditorMode, item: MediaItem?) -> MiniPlayerModel {
        MiniPlayerModel.make(
            currentTime: 45,
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
    }

    @MainActor
    func test_render_cueShowEmptyStates() throws {
        let cases = [
            RenderCase(name: "miniplayer-cue-dark", model: model(editorMode: .cue, item: populatedItem()), playing: true),
            RenderCase(name: "miniplayer-show-dark", model: model(editorMode: .show, item: populatedItem()), playing: true),
            RenderCase(name: "miniplayer-empty-dark", model: model(editorMode: .cue, item: nil), playing: false)
        ]

        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("screenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        for testCase in cases {
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
