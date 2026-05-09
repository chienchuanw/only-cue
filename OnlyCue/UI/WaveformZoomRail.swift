import SwiftUI

/// Hover-revealed minimal zoom rail. One view serves both axes — caller picks `.vertical`
/// or `.horizontal` and supplies an `applyDrag` closure that captures the baseline at
/// drag start and forwards the translation to the appropriate controller.
///
/// The rail owns no zoom math. It only:
///   - renders a thin translucent strip along the chosen edge,
///   - shows a magnifier badge with the live zoom level,
///   - runs a `DragGesture` and forwards `(translation, baseline, anchorFraction)` to
///     the closure.
struct WaveformZoomRail: View {

    enum Axis {
        case vertical
        case horizontal
    }

    let axis: Axis
    let zoom: CGFloat
    let isVisible: Bool
    /// Called on each drag change. `translation` is the axis-relevant component of
    /// the drag (height for vertical, width for horizontal). `baseline` is the zoom
    /// captured at drag start. `anchorFraction` is the cursor's start position
    /// normalised to viewport width (horizontal axis only — ignored when the rail
    /// is vertical; caller passes a stable default in that case).
    let onDrag: (_ translation: CGFloat, _ baseline: CGFloat, _ anchorFraction: CGFloat) -> Void
    /// Called on a double-click of the rail. Caller resets the relevant axis.
    let onResetRequested: () -> Void

    @State private var dragBaseline: CGFloat?
    @State private var isHovering: Bool = false

    private static let railThickness: CGFloat = 14
    private static let restingFill = Color.secondary.opacity(0.18)
    private static let hoverFill = Color.secondary.opacity(0.40)

    var body: some View {
        Group {
            switch axis {
            case .vertical:
                verticalRail
            case .horizontal:
                horizontalRail
            }
        }
        .opacity(isVisible || dragBaseline != nil ? 1 : 0)
        .animation(.easeInOut(duration: isVisible ? 0.12 : 0.20), value: isVisible)
        .accessibilityIdentifier(axis == .vertical
            ? "waveformVerticalZoomRail"
            : "waveformHorizontalZoomRail")
    }

    private var verticalRail: some View {
        Rectangle()
            .fill(isHovering ? Self.hoverFill : Self.restingFill)
            .frame(width: Self.railThickness)
            .overlay(badge)
            .contentShape(Rectangle())
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
                        if dragBaseline == nil { dragBaseline = zoom }
                        if let baseline = dragBaseline {
                            onDrag(value.translation.height, baseline, 0.5)
                        }
                    }
                    .onEnded { _ in dragBaseline = nil }
            )
            .onTapGesture(count: 2) { onResetRequested() }
    }

    private var horizontalRail: some View {
        GeometryReader { proxy in
            Rectangle()
                .fill(isHovering ? Self.hoverFill : Self.restingFill)
                .frame(height: Self.railThickness)
                .overlay(alignment: .trailing) { badge.padding(.trailing, 6) }
                .contentShape(Rectangle())
                .onHover { hovering in
                    isHovering = hovering
                    if hovering {
                        NSCursor.resizeLeftRight.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if dragBaseline == nil { dragBaseline = zoom }
                            if let baseline = dragBaseline {
                                let width = max(proxy.size.width, 1)
                                let anchor = max(min(value.startLocation.x / width, 1), 0)
                                onDrag(value.translation.width, baseline, anchor)
                            }
                        }
                        .onEnded { _ in dragBaseline = nil }
                )
                .onTapGesture(count: 2) { onResetRequested() }
        }
        .frame(height: Self.railThickness)
    }

    private var badge: some View {
        HStack(spacing: 3) {
            Image(systemName: "magnifyingglass")
                .imageScale(.small)
            Text(String(format: "%.1f×", Double(zoom)))
                .font(.caption2.monospacedDigit())
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .background(.thinMaterial, in: Capsule())
        .allowsHitTesting(false)
    }
}
