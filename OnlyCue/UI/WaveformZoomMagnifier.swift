import AppKit
import SwiftUI

/// Hover-revealed magnifier glyph rendered on the right edge of the waveform.
/// Drag-to-zoom affordance for horizontal zoom: X delta scales the zoom from
/// the baseline captured at drag start. Double-click resets to 1×.
///
/// Owns no zoom math. Captures the baseline at drag start and forwards the
/// per-tick translation to `onDrag` for the container to dispatch through the
/// zoom controller.
struct WaveformZoomMagnifier: View {

    let horizontalZoom: CGFloat
    let isVisible: Bool
    let onDrag: (MagnifierDrag) -> Void
    let onResetRequested: () -> Void

    @State private var dragBaseline: CGFloat?
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
                    dragBaseline = horizontalZoom
                }
                guard let baseline = dragBaseline else { return }

                onDrag(MagnifierDrag(
                    translationX: value.translation.width,
                    hBaseline: baseline
                ))
            }
            .onEnded { _ in
                dragBaseline = nil
            }
    }
}

/// Per-tick drag payload forwarded from `WaveformZoomMagnifier` to the
/// container's dispatch helper.
struct MagnifierDrag {
    let translationX: CGFloat
    let hBaseline: CGFloat
}
