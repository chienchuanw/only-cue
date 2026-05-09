import SwiftUI

/// Thin drag-region rendered below the waveform that translates vertical drag into
/// live `WaveformVerticalZoomController` updates. Drag up = zoom in; drag down = zoom out.
/// Baseline zoom is captured at drag start so the math stays consistent with the user's
/// reference frame across a single continuous drag (avoids clamping artifacts).
struct VerticalZoomDragHandle: View {

    let controller: WaveformVerticalZoomController

    @State private var dragBaseline: CGFloat?
    @State private var isHovering: Bool = false

    var body: some View {
        Rectangle()
            .fill(Color.secondary.opacity(isHovering ? 0.5 : 0.2))
            .frame(height: 10)
            .accessibilityIdentifier("waveformVerticalZoomDragHandle")
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    NSCursor.resizeUpDown.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if dragBaseline == nil {
                            dragBaseline = controller.zoom
                        }
                        if let baseline = dragBaseline {
                            controller.applyDrag(
                                translation: value.translation.height,
                                baseline: baseline
                            )
                        }
                    }
                    .onEnded { _ in
                        dragBaseline = nil
                    }
            )
    }
}
