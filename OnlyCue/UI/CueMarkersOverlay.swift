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
    /// When false (Lyric / Show mode) the overlay stops hit-testing, so
    /// clicks fall through to the seek surface below.
    var isEditable: Bool = true
    /// Lyric mode dims markers so the lyric ribbons read as the active
    /// surface. Show mode keeps markers solid (audit §9.1) — the dimming is
    /// applied to the underlying waveform peaks in `WaveformContainer`
    /// instead, so the cue list still reads at a glance during a show run.
    var isDimmed: Bool = false

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
        .opacity(isDimmed ? 0.35 : 1)
        .allowsHitTesting(isEditable)
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
        /// Pin-badge box (Figma 318:1303 — a rounded top with a downward
        /// pointer). The cue number sits centered inside the badge.
        let pinWidth: CGFloat
        let pinHeight: CGFloat

        static let normal = Self(lineWidth: 2, pinWidth: 18, pinHeight: 20)
        static let selected = Self(lineWidth: 3, pinWidth: 22, pinHeight: 24)

        static func style(isSelected: Bool) -> Self {
            isSelected ? .selected : .normal
        }
    }

    /// Inset cue-number type size — Inter Semi Bold 10 in Figma 318:1303.
    static let markerNumberFontSize: CGFloat = 10

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
    private static let haloPadding: CGFloat = 8
    private static let haloOpacity: Double = 0.35
    private static let haloBlurRadius: CGFloat = 2
    /// Pin pointer (the downward tip) and corner radius (Figma 318:1303).
    static let pinPointerHeight: CGFloat = 4
    static let pinCornerRadius: CGFloat = 4

    @State private var isHovered: Bool = false

    private var style: MarkerStyle { MarkerStyle.style(isSelected: isSelected) }

    private var haloVisible: Bool {
        Self.showHalo(isHovered: isHovered, isSelected: isSelected)
    }

    private var frameWidth: CGFloat { max(Self.hitWidth, style.pinWidth) }

    var body: some View {
        ZStack(alignment: .top) {
            // Full-height cue line — the flexible Rectangle accepts the well's
            // proposed height, so the line spans the waveform.
            Rectangle()
                .fill(markerColor)
                .frame(width: style.lineWidth)
                .opacity(0.85)
            // Full-height invisible hit target for drag / seek.
            Capsule()
                .fill(.clear)
                .frame(width: Self.hitWidth)
                .onHover { inside in
                    isHovered = inside
                    if inside {
                        NSCursor.resizeLeftRight.push()
                    } else {
                        NSCursor.pop()
                    }
                }
            // Hover halo behind the pin badge.
            CuePinShape(pointerHeight: Self.pinPointerHeight, cornerRadius: Self.pinCornerRadius)
                .fill(markerColor)
                .frame(width: style.pinWidth + Self.haloPadding, height: style.pinHeight + Self.haloPadding)
                .opacity(haloVisible ? Self.haloOpacity : 0)
                .blur(radius: Self.haloBlurRadius)
                .animation(.easeOut(duration: 0.12), value: haloVisible)
                .allowsHitTesting(false)
            pinBadge
        }
        .frame(width: frameWidth)
        .offset(x: baseX + visualOffset - frameWidth / 2)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in onDragChanged(value.translation.width) }
                .onEnded { value in onDragEnded(value.translation.width) }
        )
        // The parent overlay uses `.accessibilityElement(children: .contain)`
        // so the marker is queryable by id without needing `.combine` here —
        // adding `.combine` would create a duplicate AX element wrapper.
        .accessibilityIdentifier("cueMarker-\(cue.id.uuidString)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// The colored pin badge (Figma 318:1303) with the cue number centered
    /// inside it; the number color flips to stay legible on light vs dark fills.
    private var pinBadge: some View {
        ZStack {
            CuePinShape(pointerHeight: Self.pinPointerHeight, cornerRadius: Self.pinCornerRadius)
                .fill(markerColor)
            if let number = cue.cueNumber {
                Text(FadeTime.formatNumber(number))
                    .font(.system(size: Self.markerNumberFontSize, weight: .semibold))
                    .foregroundStyle(numberColor)
                    .fixedSize()
                    // Center within the rounded body, above the pointer tip.
                    .offset(y: -Self.pinPointerHeight / 2)
                    .accessibilityIdentifier("cueMarkerLabel-\(cue.id.uuidString)")
            }
        }
        .frame(width: style.pinWidth, height: style.pinHeight)
        .allowsHitTesting(false)
    }

    private var markerColor: Color {
        guard let hex = resolvedColorHex else { return .accentColor }
        return Color(hex: hex) ?? .accentColor
    }

    private var numberColor: Color {
        Self.numberColor(forHex: resolvedColorHex)
    }

    /// Dark glyph on a light fill, light glyph on a dark fill — matches Figma's
    /// dark `#1f1c1a` number for the bright cue colors while staying legible on
    /// dark cue colors (e.g. indigo).
    static func numberColor(forHex hex: String?) -> Color {
        guard let hex, let luminance = relativeLuminance(hex: hex) else {
            return Color(red: 0.122, green: 0.110, blue: 0.102) // Figma #1f1c1a
        }
        return luminance > 0.5
            ? Color(red: 0.122, green: 0.110, blue: 0.102)
            : .white
    }

    /// Approximate relative luminance (0…1) from a `#RRGGBB` hex; nil if unparsable.
    static func relativeLuminance(hex: String) -> Double? {
        var clean = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("#") { clean.removeFirst() }
        guard clean.count == 6, let value = UInt32(clean, radix: 16) else { return nil }
        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        return 0.2126 * red + 0.7152 * green + 0.0722 * blue
    }
}

/// A map-pin badge: a rounded rectangle body with a centered downward pointer
/// at the bottom (Figma 318:1303 CueMarker pin).
struct CuePinShape: Shape {

    var pointerHeight: CGFloat = 4
    var cornerRadius: CGFloat = 4

    func path(in rect: CGRect) -> Path {
        let bodyHeight = max(0, rect.height - pointerHeight)
        var path = Path()
        path.addRoundedRect(
            in: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: bodyHeight),
            cornerSize: CGSize(width: cornerRadius, height: cornerRadius)
        )
        // Downward pointer centered on the body's bottom edge.
        path.move(to: CGPoint(x: rect.midX - pointerHeight, y: bodyHeight))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX + pointerHeight, y: bodyHeight))
        path.closeSubpath()
        return path
    }
}
