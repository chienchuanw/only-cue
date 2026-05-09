import AppKit
import SwiftUI

/// Hover-revealed magnifier glyph rendered on the right edge of the waveform.
/// Single affordance for both horizontal and vertical zoom — exposes each axis
/// through a single `DragGesture` (X delta → horizontal, Y delta → vertical).
/// Holding Shift locks to the dominant axis (one-shot per drag, see
/// `MagnifierAxisLock`). Double-click resets both axes.
///
/// Owns no zoom math. Captures both baselines at drag start and forwards the
/// resolved per-tick translations to `onDrag` for the container to dispatch
/// through the two zoom controllers.
struct WaveformZoomMagnifier: View {

    let horizontalZoom: CGFloat
    let verticalZoom: CGFloat
    let isVisible: Bool
    let onDrag: (MagnifierDrag) -> Void
    let onResetRequested: () -> Void

    @State private var dragBaseline: (h: CGFloat, v: CGFloat)?
    @State private var axisLockState: MagnifierAxisLock.State = .unresolved
    @State private var isHovering: Bool = false

    var body: some View {
        Image(systemName: "magnifyingglass")
            .foregroundStyle(.secondary)
            .padding(6)
            .background(isHovering ? .thinMaterial : .ultraThinMaterial, in: Circle())
            .contentShape(Circle())
        .opacity(isVisible || dragBaseline != nil ? 1 : 0)
        .animation(.easeInOut(duration: isVisible ? 0.12 : 0.20), value: isVisible)
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                NSCursor.crosshair.push()
            } else {
                NSCursor.pop()
            }
        }
        .onDisappear {
            if isHovering {
                NSCursor.pop()
                isHovering = false
            }
        }
        .gesture(dragGesture)
        .onTapGesture(count: 2) { onResetRequested() }
        .accessibilityIdentifier("waveformZoomMagnifier")
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragBaseline == nil {
                    dragBaseline = (h: horizontalZoom, v: verticalZoom)
                }
                guard let baseline = dragBaseline else { return }

                let resolution = MagnifierAxisLock.resolve(
                    translationX: value.translation.width,
                    translationY: value.translation.height,
                    isShiftHeld: NSEvent.modifierFlags.contains(.shift),
                    currentState: axisLockState
                )
                axisLockState = resolution.nextState

                onDrag(MagnifierDrag(
                    translationX: resolution.effectiveX,
                    translationY: resolution.effectiveY,
                    hBaseline: baseline.h,
                    vBaseline: baseline.v
                ))
            }
            .onEnded { _ in
                dragBaseline = nil
                axisLockState = .unresolved
            }
    }
}

/// Per-tick drag payload forwarded from `WaveformZoomMagnifier` to the
/// container's dispatch helper. `translationX` / `translationY` are already
/// axis-lock-resolved (zeroed on the locked-out axis when Shift dictates).
struct MagnifierDrag {
    let translationX: CGFloat
    let translationY: CGFloat
    let hBaseline: CGFloat
    let vBaseline: CGFloat
}
