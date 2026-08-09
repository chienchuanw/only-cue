import XCTest
import SwiftUI
import AppKit
@testable import OnlyCue

/// The consolidated figma↔app fidelity contract. Each assertion pins a
/// load-bearing value to its Figma spec (node id in the comment) so a
/// regression fails CI deterministically — these are renderer-independent,
/// unlike a pixel diff. Per-feature suites (DSColorTests, WaveformViewColorTests,
/// CueListColumnWidthsTests, PreviewLayoutTests, CompactDurationTests) hold the
/// exhaustive cases; this file is the single greppable gate and the canonical
/// list of "things that must keep matching the design system".
///
/// Process for keeping this honest lives in `docs/design/fidelity-gate.md`.
final class FigmaFidelityTests: XCTestCase {

    /// Resolves a token's red sRGB component under a given appearance.
    private func red(of color: Color, appearance name: NSAppearance.Name) throws -> CGFloat {
        let appearance = try XCTUnwrap(NSAppearance(named: name))
        var resolved: NSColor?
        appearance.performAsCurrentDrawingAppearance {
            resolved = NSColor(color).usingColorSpace(.sRGB)
        }
        return try XCTUnwrap(resolved).redComponent
    }

    /// Dark-only main window (ADR-029): chrome resolves dark even under Light.
    func test_darkOnlyChrome() throws {
        XCTAssertLessThan(try red(of: DS.Color.surface, appearance: .aqua), 0.2)
        XCTAssertGreaterThan(try red(of: DS.Color.textPrimary, appearance: .aqua), 0.85)
        XCTAssertEqual(AppAppearance.production, .darkAqua)
    }

    /// Achromatic waveform (ADR-024 / Figma 318:1254): a DS neutral, not the accent.
    func test_waveformIsAchromatic() {
        XCTAssertEqual(WaveformView(buckets: []).color, DS.Color.textSecondary)
        XCTAssertNotEqual(WaveformView(buckets: []).color, DS.Color.cueIndigo)
    }

    /// Preview video/waveform split (Figma 318:1639): the waveform band is a
    /// ~quarter of the well, and the video stays dominant (band <= half).
    func test_previewVideoSplitProportion() {
        let band = PreviewLayout.videoTimelineHeight(totalHeight: 602, breakdown: false)
        XCTAssertEqual(band, 602 * 0.26, accuracy: 1)
        XCTAssertLessThanOrEqual(
            PreviewLayout.videoTimelineHeight(totalHeight: 200, breakdown: false),
            100
        )
    }

    /// Sidebar clip durations are compact m:ss (ADR-028 amendment / Figma 318:1238),
    /// not framerate SMPTE.
    func test_sidebarDurationsAreCompact() {
        XCTAssertEqual(TimeFormat.compactDuration(222), "3:42")
        XCTAssertEqual(TimeFormat.compactDuration(3700), "1:01:40")
    }

    /// Cue markers are colored pin badges (Figma 318:1303 — 18×20 pin with the
    /// number centered inside), not a number stacked above a small cap.
    func test_cueMarkerPinSizeMatchesFigma() {
        XCTAssertEqual(CueMarkerView.MarkerStyle.normal.pinWidth, 18)
        XCTAssertEqual(CueMarkerView.MarkerStyle.normal.pinHeight, 20)
        XCTAssertEqual(CueMarkerView.markerNumberFontSize, 10)
        // Selected markers grow the pin, keeping the number legible.
        XCTAssertGreaterThan(
            CueMarkerView.MarkerStyle.selected.pinWidth,
            CueMarkerView.MarkerStyle.normal.pinWidth
        )
    }

    /// Cue/Lyric/Show switcher is left-aligned with a 16pt leading inset
    /// (Figma 318:1250 — EditorModeSwitcher at x=16), not centered.
    func test_switcherLeadingInsetMatchesFigma() {
        XCTAssertEqual(PreviewLayout.switcherLeadingInset, 16)
    }

    /// Sidebar row is a single line (Figma 318:1238 / component 77:43): 14pt
    /// kind icon, 10pt mono clip length, and the edit pencil is hidden at rest
    /// (it fades in only on hover).
    func test_sidebarRowSingleLineMetrics() {
        XCTAssertEqual(ItemRowMetrics.iconSize, 14)
        XCTAssertEqual(ItemRowMetrics.durationFontSize, 10)
        XCTAssertEqual(ItemRowMetrics.pencilOpacity(isHovered: false), 0)
        XCTAssertEqual(ItemRowMetrics.pencilOpacity(isHovered: true), 1)
    }
}
