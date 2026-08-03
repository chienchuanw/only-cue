import AppKit
import SwiftUI

/// The draggable divider between the centre pane and the inspector.
///
/// Deliberately a plain SwiftUI `Divider()` with a gesture, NOT an
/// `HSplitView` or `.inspector`: any `NSSplitView`-backed split in the detail
/// column double-counts the sidebar into the window's minimum width and pins
/// the populated window at 1416pt, past the 1280pt design width (#617). The
/// gesture writes a width into state, which feeds the existing frame contract
/// — no AppKit split view is involved, so that mechanism cannot re-engage.
struct InspectorDivider: View {

    @Binding var width: CGFloat

    /// The width when the current drag began. `DragGesture.translation` is
    /// cumulative from the drag's start, so adding it to the *live* width each
    /// frame would compound and make the divider run away from the cursor.
    @State private var dragStartWidth: CGFloat?

    /// A 1pt line is far too small a target. The hit area is widened to
    /// `DS.Space.md` (12pt) around it — the standard macOS splitter tolerance
    /// — without changing the layout, because the overlay does not participate
    /// in sizing.
    private var hitArea: some View {
        Color.clear
            .frame(width: DS.Space.md)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(dragGesture)
    }

    /// `minimumDistance: 1`, not 0: a 0pt minimum makes the divider swallow
    /// plain clicks that land in the widened hit area, which overlaps the
    /// waveform's click-to-seek target (project CLAUDE.md's SwiftUI gesture
    /// caution). 1pt still feels instant while letting a click through.
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                let start = dragStartWidth ?? width
                if dragStartWidth == nil { dragStartWidth = start }
                // Dragging LEFT (negative translation) widens the inspector,
                // because the inspector is the right-hand pane.
                width = min(
                    max(start - value.translation.width, CueListInspectorMetrics.minWidth),
                    CueListInspectorMetrics.maxWidth
                )
            }
            .onEnded { _ in dragStartWidth = nil }
    }

    var body: some View {
        Divider()
            .overlay(hitArea)
            .accessibilityElement()
            .accessibilityIdentifier("inspectorDivider")
            .accessibilityLabel("Inspector width")
            .accessibilityValue("\(Int(width)) points")
            .accessibilityAddTraits(.isButton)
    }
}
