import AppKit
import SwiftUI

struct CueMarkersOverlay: View {

    let cues: [Cue]
    let duration: TimeInterval
    var resolveColorHex: (Cue) -> String? = { _ in nil }
    var selectedCueIDs: Set<Cue.ID> = []
    var tempoGrid: DerivedTempoGrid = DerivedTempoGrid(segments: [])
    /// Plain marker click → replace the selection with this cue.
    var onSelectCue: (Cue.ID) -> Void = { _ in }
    /// ⌘- (or ⇧-) marker click → toggle this cue in/out of the selection.
    var onToggleCue: (Cue.ID) -> Void = { _ in }
    var onSeek: (TimeInterval) -> Void = { _ in }
    var onRetime: (Cue.ID, TimeInterval) -> Void = { _, _ in }
    /// Rigid shift of every cue in the set by the same Δt (clamped at 0 per cue),
    /// committed as a single undo entry. Used by group drag.
    var onNudge: (Set<Cue.ID>, TimeInterval) -> Void = { _, _ in }

    @State private var activeDrag: ActiveDrag?

    fileprivate struct ActiveDrag: Equatable {
        let grabbedID: Cue.ID
        let movingIDs: Set<Cue.ID>
        let isGroup: Bool
        var dxRaw: CGFloat
        var dxApplied: CGFloat
    }

    private static let dragThreshold: CGFloat = 4

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                ForEach(cues) { cue in
                    CueMarkerView(
                        cue: cue,
                        resolvedColorHex: resolveColorHex(cue),
                        baseX: CueMarkersGeometry.position(
                            forTime: cue.time,
                            width: geometry.size.width,
                            duration: duration
                        ),
                        isSelected: selectedCueIDs.contains(cue.id),
                        visualOffset: visualOffset(for: cue.id),
                        onDragChanged: { translationWidth in
                            handleDragChanged(grabbedID: cue.id, translationWidth: translationWidth, width: geometry.size.width)
                        },
                        onDragEnded: { translationWidth in
                            handleDragEnded(grabbedID: cue.id, translationWidth: translationWidth, width: geometry.size.width)
                        }
                    )
                }
            }
        }
        // `.contain` keeps the overlay a queryable element AND lets XCUITest
        // walk its children — important so individual `cueMarker-<id>` views
        // surface in the AX tree. Without this, GeometryReader's default
        // accessibility container collapses children into the overlay.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cueMarkersOverlay")
    }

    private func visualOffset(for id: Cue.ID) -> CGFloat {
        guard let drag = activeDrag, drag.movingIDs.contains(id) else { return 0 }
        return drag.dxApplied
    }

    private func cue(for id: Cue.ID) -> Cue? {
        cues.first(where: { $0.id == id })
    }

    private func handleDragChanged(grabbedID: Cue.ID, translationWidth: CGFloat, width: CGFloat) {
        // Defer starting "drag mode" until raw translation crosses the tap/drag
        // threshold. Otherwise the first onChanged (translation == 0) would
        // hijack modifier-clicks: ⌘-click on an unselected marker would replace
        // the selection here, then the subsequent tap path would toggle the
        // grabbed cue out — netting an empty selection.
        if activeDrag == nil {
            guard abs(translationWidth) >= Self.dragThreshold else { return }
            let isGroup = selectedCueIDs.contains(grabbedID) && selectedCueIDs.count >= 2
            let moving: Set<Cue.ID>
            if isGroup {
                moving = selectedCueIDs
            } else {
                // Solo drag of an unselected marker while a multi-selection exists:
                // replace selection with just this cue, mirroring plain-click.
                if !selectedCueIDs.contains(grabbedID) && selectedCueIDs.count >= 2 {
                    onSelectCue(grabbedID)
                }
                moving = [grabbedID]
            }
            activeDrag = ActiveDrag(
                grabbedID: grabbedID,
                movingIDs: moving,
                isGroup: isGroup,
                dxRaw: translationWidth,
                dxApplied: translationWidth
            )
        }
        guard var drag = activeDrag else { return }
        drag.dxRaw = translationWidth
        drag.dxApplied = applySnap(dxRaw: translationWidth, grabbedID: drag.grabbedID, width: width)
        activeDrag = drag
    }

    private func handleDragEnded(grabbedID: Cue.ID, translationWidth: CGFloat, width: CGFloat) {
        defer { activeDrag = nil }
        // Tap-vs-drag gate uses RAW translation, not post-snap dx. Post-snap dx
        // can clear the threshold even when the user only clicked (e.g. Shift-
        // click landing a couple of pixels off a beat would snap onto the beat
        // and otherwise trigger an unintended retime).
        if abs(translationWidth) < Self.dragThreshold {
            handleTap(grabbedID: grabbedID)
            return
        }
        guard let drag = activeDrag, drag.grabbedID == grabbedID else {
            handleTap(grabbedID: grabbedID)
            return
        }
        let dxFinal = applySnap(dxRaw: translationWidth, grabbedID: grabbedID, width: width)
        guard let grabbed = cue(for: grabbedID) else { return }
        let newTime = CueMarkersGeometry.time(
            originalTime: grabbed.time,
            dx: dxFinal,
            width: width,
            duration: duration
        )
        let deltaT = newTime - grabbed.time
        if drag.isGroup {
            onNudge(drag.movingIDs, deltaT)
        } else {
            onRetime(grabbedID, newTime)
        }
    }

    private func handleTap(grabbedID: Cue.ID) {
        let modifiers = NSEvent.modifierFlags
        let extending = modifiers.contains(.command) || modifiers.contains(.shift)
        if extending {
            onToggleCue(grabbedID)
        } else {
            onSelectCue(grabbedID)
            if let grabbed = cue(for: grabbedID) {
                onSeek(grabbed.time)
            }
        }
    }

    private func applySnap(dxRaw: CGFloat, grabbedID: Cue.ID, width: CGFloat) -> CGFloat {
        // Shift held + tempo grid available → snap anchor (grabbed cue) to nearest beat.
        guard NSEvent.modifierFlags.contains(.shift),
              !tempoGrid.isEmpty,
              let anchor = cue(for: grabbedID) else {
            return dxRaw
        }
        return CueMarkersGeometry.snapDeltaToBeat(
            dxPixels: dxRaw,
            anchorTime: anchor.time,
            grid: tempoGrid,
            width: width,
            duration: duration
        )
    }
}

struct CueMarkerView: View {

    struct MarkerStyle: Equatable {
        let lineWidth: CGFloat
        let capWidth: CGFloat
        let capHeight: CGFloat

        static let normal = Self(lineWidth: 2, capWidth: 10, capHeight: 8)
        static let selected = Self(lineWidth: 3, capWidth: 14, capHeight: 12)

        static func style(isSelected: Bool) -> Self {
            isSelected ? .selected : .normal
        }
    }

    /// Whether to render the hover halo behind the cap. Selected markers
    /// suppress the halo: the selected style (thicker line + larger cap)
    /// already conveys focus, and stacking both reads as noisy.
    static func showHalo(isHovered: Bool, isSelected: Bool) -> Bool {
        isHovered && !isSelected
    }

    let cue: Cue
    var resolvedColorHex: String?
    let baseX: CGFloat
    var isSelected: Bool = false
    var visualOffset: CGFloat = 0
    var onDragChanged: (_ translationWidth: CGFloat) -> Void = { _ in }
    var onDragEnded: (_ translationWidth: CGFloat) -> Void = { _ in }

    private static let hitWidth: CGFloat = 14
    private static let labelGap: CGFloat = 1

    private var style: MarkerStyle { MarkerStyle.style(isSelected: isSelected) }

    var body: some View {
        VStack(spacing: Self.labelGap) {
            if let number = cue.cueNumber {
                Text(FadeTime.formatNumber(number))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .accessibilityIdentifier("cueMarkerLabel-\(cue.id.uuidString)")
            }
            ZStack(alignment: .top) {
                Capsule()
                    .fill(.clear)
                    .frame(width: Self.hitWidth)
                    .onHover { inside in
                        if inside {
                            NSCursor.resizeLeftRight.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                Rectangle()
                    .fill(markerColor)
                    .frame(width: style.lineWidth)
                    .opacity(0.85)
                Capsule()
                    .fill(markerColor)
                    .frame(width: style.capWidth, height: style.capHeight)
            }
        }
        .frame(width: Self.hitWidth)
        .offset(x: baseX + visualOffset - Self.hitWidth / 2)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in onDragChanged(value.translation.width) }
                .onEnded { value in onDragEnded(value.translation.width) }
        )
        // The parent overlay uses `.accessibilityElement(children: .contain)`
        // so the marker is queryable by id without needing `.combine` here —
        // adding `.combine` would create a duplicate AX element wrapper.
        .accessibilityIdentifier("cueMarker-\(cue.id.uuidString)")
    }

    private var markerColor: Color {
        guard let hex = resolvedColorHex else { return .accentColor }
        return Color(hex: hex) ?? .accentColor
    }
}
