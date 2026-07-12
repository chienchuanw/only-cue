import AVFoundation
import XCTest
@testable import OnlyCue

/// #611: deterministic ruler for the reported audio↔visual sync offset.
/// A click at a known time is pushed through the real pipeline
/// (generate → downsample → column x) and its drawn position is compared
/// against the playhead mapping for the same time. Any fixed offset in the
/// static pipeline shows up here as a measured pixel delta, replacing
/// perception-based testing.
final class WaveformClickAlignmentTests: XCTestCase {

    func test_bucketer_downsample_preservesClickPosition() {
        // A spike at index 1000 of 2000, downsampled to 300 columns, must stay
        // at the same fractional position (0.5) — a shifted argmax here would
        // smear every transient sideways on screen.
        var peaks = [Float](repeating: 0.1, count: 2000)
        peaks[1000] = 1.0

        let columns = WaveformPeakBucketer.bucket(peaks: peaks, into: 300)

        let argmax = columns.indices.max(by: { columns[$0] < columns[$1] }) ?? -1
        let fraction = (Double(argmax) + 0.5) / Double(columns.count)
        XCTAssertEqual(fraction, 0.5, accuracy: 1.0 / Double(columns.count))
    }

    func test_endToEnd_clickColumnX_matchesPlayheadXAtClickTime() async throws {
        // Full pipeline: 20s WAV with a click at exactly 10.000s → peaks →
        // downsample to an 800pt-wide view → the drawn column of the click vs
        // where the playhead sits at 10.000s. They must agree within one
        // column width, or the waveform lies about when things sound.
        let url = try SilentAudioFixture.makeClickWAV(duration: 20, clickAt: 10)
        defer { try? FileManager.default.removeItem(at: url) }
        let asset = AVURLAsset(url: url)
        let width: CGFloat = 800
        let duration: TimeInterval = 20

        let peaks = try await WaveformGenerator.peaks(for: asset, resolution: 2000)
        let columns = WaveformPeakBucketer.bucket(peaks: peaks, into: Int(width))
        let argmax = try XCTUnwrap(columns.indices.max(by: { columns[$0] < columns[$1] }))
        let clickX = WaveformView.columnX(index: argmax, count: columns.count, width: width)
        let playheadX = CueMarkersGeometry.position(forTime: 10, width: width, duration: duration)

        let columnWidth = width / CGFloat(columns.count)
        XCTAssertEqual(
            clickX,
            playheadX,
            accuracy: columnWidth,
            "click drawn at x=\(clickX) but playhead for 10.000s at x=\(playheadX) — measured offset \((clickX - playheadX) / width * CGFloat(duration))s"
        )
    }
}
