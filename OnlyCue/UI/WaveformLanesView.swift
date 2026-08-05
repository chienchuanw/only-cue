import SwiftUI

// MARK: - Layout math (pure, testable)

/// Pure layout helper for multi-lane waveform height calculation.
///
/// The denominator invariant: `laneCount` is always treated as ≥ 1 (the
/// `laneCount <= 1` guard collapses to `totalHeight` with no division), and
/// the raw result is floored at 1 pt so a lane is never invisible or negative
/// even when a large gap squeezes the available space below zero.
enum WaveformLaneLayout {

    /// Height of a single lane given `totalHeight`, `laneCount`, and inter-lane
    /// `gap`.
    ///
    /// Formula: `(totalHeight - gap*(laneCount-1)) / laneCount`
    ///
    /// - A single lane (or any `laneCount <= 1`) returns `totalHeight` with no
    ///   gap applied.
    /// - The result is floored at 1 pt (hairline minimum) so the lane is never
    ///   zero or negative.
    static func laneHeight(totalHeight: CGFloat, laneCount: Int, gap: CGFloat) -> CGFloat {
        guard laneCount > 1 else { return max(totalHeight, 1) }
        let raw = (totalHeight - gap * CGFloat(laneCount - 1)) / CGFloat(laneCount)
        return max(raw, 1)
    }
}

// MARK: - View

/// Renders one `WaveformView` per channel stacked vertically, each occupying
/// an equal share of `height` with `DS.Space.xs` gaps between lanes.
///
/// A single lane is visually identical to a bare `WaveformView(peaks:)` at
/// full `height` — no gap is applied and the frame equals `totalHeight`.
struct WaveformLanesView: View {

    let lanes: [[Float]]
    let height: CGFloat

    /// Gap between lanes — uses the xs (4 pt) spacing token so adjacent
    /// waveforms read as a tight group, not isolated panels.
    private let gap: CGFloat = DS.Space.xs

    init(lanes: [[Float]], height: CGFloat) {
        self.lanes = lanes
        self.height = height
    }

    var body: some View {
        let laneHeight = WaveformLaneLayout.laneHeight(
            totalHeight: height,
            laneCount: lanes.count,
            gap: gap
        )
        VStack(spacing: gap) {
            ForEach(Array(lanes.enumerated()), id: \.offset) { index, peaks in
                WaveformView(peaks: peaks)
                    .frame(height: laneHeight)
                    .accessibilityIdentifier("waveformLane.\(index)")
            }
        }
        .accessibilityIdentifier("waveformLanes")
    }
}
