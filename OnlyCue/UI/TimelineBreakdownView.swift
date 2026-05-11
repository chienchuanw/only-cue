import SwiftUI

/// The timeline broken into one lane per visible `CuePointType` — so a
/// programmer can read "lighting only" or "sound only" cues at a glance. Each
/// lane: a colour-swatch + name label and a hide button on the left, then a
/// track holding only that Type's cue markers (positioned by
/// `CueMarkersGeometry.position`, the same mapping the waveform overlay uses).
/// A single playhead line spans every lane. Hidden Types collapse into a
/// "+N hidden" button that shows them all again. Lanes scroll vertically if
/// they overflow the timeline area; there's no horizontal zoom in v1.
///
/// Shown in `PreviewPane` in place of the waveform view when `View → Show
/// Timeline Breakdown` is on. Lane visibility is `CuePointType.isVisible`,
/// which persists in `.cuelist`; toggling it goes through `CueCommands` so
/// it's undoable.
struct TimelineBreakdownView: View {

    let cues: [Cue]
    let types: [CuePointType]
    let duration: TimeInterval
    var selectedCueID: Cue.ID?
    var onSelectCue: (Cue.ID) -> Void = { _ in }
    var onSeek: (TimeInterval) -> Void = { _ in }
    var onHideType: (CuePointType.ID) -> Void = { _ in }
    var onShowAllTypes: () -> Void = {}
    var engine: PlayerEngine?

    private static let laneHeight: CGFloat = 30
    private static let labelWidth: CGFloat = 116
    private static let labelTrackGap: CGFloat = 6

    var body: some View {
        let lanes = TimelineBreakdownLayout.lanes(cues: cues, types: types)
        let hidden = TimelineBreakdownLayout.hiddenCount(types: types)
        GeometryReader { proxy in
            let trackWidth = max(0, proxy.size.width - Self.labelWidth - Self.labelTrackGap)
            VStack(spacing: 0) {
                if lanes.isEmpty {
                    placeholder
                } else {
                    lanesScroll(lanes, trackWidth: trackWidth)
                        .overlay(alignment: .topLeading) {
                            playhead(trackWidth: trackWidth)
                        }
                }
                if hidden > 0 {
                    hiddenFooter(hidden)
                }
            }
        }
        .padding(.horizontal, 8)
        .accessibilityIdentifier("timelineBreakdown")
    }

    private func lanesScroll(_ lanes: [TimelineBreakdownLayout.Lane], trackWidth: CGFloat) -> some View {
        ScrollView(.vertical) {
            VStack(spacing: 1) {
                ForEach(lanes) { lane in
                    laneRow(lane, trackWidth: trackWidth)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func laneRow(_ lane: TimelineBreakdownLayout.Lane, trackWidth: CGFloat) -> some View {
        HStack(spacing: Self.labelTrackGap) {
            laneLabel(lane)
            laneTrack(lane, width: trackWidth)
        }
        .frame(height: Self.laneHeight)
    }

    private func laneLabel(_ lane: TimelineBreakdownLayout.Lane) -> some View {
        HStack(spacing: 5) {
            CueColorSwatch(hex: lane.colorHex, diameter: 9)
            Text(lane.name)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            Button {
                onHideType(lane.typeID)
            } label: {
                Image(systemName: "eye.slash")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help("Hide the \(lane.name) lane")
        }
        .frame(width: Self.labelWidth, alignment: .leading)
        .accessibilityIdentifier("breakdownLaneLabel.\(lane.typeID)")
    }

    private func laneTrack(_ lane: TimelineBreakdownLayout.Lane, width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.primary.opacity(0.04))
            ForEach(lane.cues) { cue in
                marker(for: cue, colorHex: lane.colorHex, trackWidth: width)
            }
        }
        .frame(width: width)
        .clipped()
        .accessibilityIdentifier("breakdownLaneTrack.\(lane.typeID)")
    }

    private func marker(for cue: Cue, colorHex: String, trackWidth: CGFloat) -> some View {
        let x = CueMarkersGeometry.position(forTime: cue.time, width: trackWidth, duration: duration)
        let selected = cue.id == selectedCueID
        let lineWidth: CGFloat = selected ? 3 : 2
        return Rectangle()
            .fill(Color(hex: colorHex) ?? .accentColor)
            .frame(width: lineWidth, height: Self.laneHeight)
            .overlay(alignment: .top) {
                if selected {
                    Circle()
                        .fill(Color(hex: colorHex) ?? .accentColor)
                        .frame(width: 7, height: 7)
                        .offset(y: -1)
                }
            }
            .contentShape(Rectangle().inset(by: -5))
            .offset(x: x - lineWidth / 2)
            .onTapGesture {
                onSelectCue(cue.id)
                onSeek(cue.time)
            }
            .help(cue.name.isEmpty ? "Cue at \(TimeFormat.hms(cue.time))" : cue.name)
    }

    @ViewBuilder
    private func playhead(trackWidth: CGFloat) -> some View {
        if let engine, duration > 0 {
            BreakdownPlayheadLine(engine: engine, duration: duration, trackWidth: trackWidth)
                .offset(x: Self.labelWidth + Self.labelTrackGap)
                .allowsHitTesting(false)
        }
    }

    private func hiddenFooter(_ hidden: Int) -> some View {
        HStack {
            Button {
                onShowAllTypes()
            } label: {
                Label("\(hidden) hidden lane\(hidden == 1 ? "" : "s")", systemImage: "eye")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help("Show all Type lanes")
            Spacer()
        }
        .padding(.top, 4)
        .accessibilityIdentifier("breakdownHiddenFooter")
    }

    private var placeholder: some View {
        Text("All Type lanes are hidden — show one to see its cues.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .multilineTextAlignment(.center)
            .accessibilityIdentifier("breakdownEmpty")
    }
}

/// The vertical playhead line for the breakdown view, in its own view so only
/// it re-renders on each `engine.currentTime` tick — the lanes (which can be
/// many) aren't invalidated. Positioned by the caller via `.offset`; this view
/// just maps current time → x within `trackWidth`.
private struct BreakdownPlayheadLine: View {
    let engine: PlayerEngine
    let duration: TimeInterval
    let trackWidth: CGFloat

    var body: some View {
        let x = CueMarkersGeometry.position(forTime: engine.currentTime, width: trackWidth, duration: duration)
        Rectangle()
            .fill(Color.red.opacity(0.85))
            .frame(width: 1.5)
            .frame(maxHeight: .infinity)
            .offset(x: x - 0.75)
    }
}
