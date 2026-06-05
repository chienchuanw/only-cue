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
        XCTAssertEqual(WaveformView(peaks: []).color, DS.Color.textSecondary)
        XCTAssertNotEqual(WaveformView(peaks: []).color, DS.Color.cueIndigo)
    }

    /// Cue-list TIME column (Figma 318:1320) keeps the full 11-char SMPTE on one
    /// line: its floor must fit `HH:MM:SS:FF` (~86pt at 13pt monospaced).
    func test_cueTimeColumnFitsSMPTE() {
        XCTAssertGreaterThanOrEqual(CueListColumnWidths.timeRange.lowerBound, 88)
        XCTAssertTrue(CueListColumnWidths.timeRange.contains(CueListColumnWidths.timeDefault))
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
}
