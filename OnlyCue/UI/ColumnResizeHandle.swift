import AppKit
import SwiftUI

/// A 6pt-wide invisible drag region for resizing a column's trailing edge.
/// Cursor flips to `resizeLeftRight` on hover; dragging writes the clamped
/// width back through the supplied binding.
///
/// The gesture requires a 2pt minimum drag distance so a plain mouse-down
/// — including click-through events fired inside `NSSplitView`'s tracking
/// loop — does not activate it. A bare activation would write the current
/// width back through `@AppStorage`, triggering `enqueueLayoutInvalidation`
/// mid-tracking and recursing constraint passes until AppKit asserts. See
/// issue #269 for the original crash.
struct ColumnResizeHandle: View {

    @Binding var width: CGFloat
    let range: ClosedRange<CGFloat>

    @State private var dragStartWidth: CGFloat?

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 6)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.set()
                } else {
                    NSCursor.arrow.set()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        if dragStartWidth == nil { dragStartWidth = width }
                        let start = dragStartWidth ?? width
                        let proposed = Self.apply(delta: value.translation.width, start: start, range: range)
                        Self.writeIfChanged($width, to: proposed)
                    }
                    .onEnded { _ in
                        dragStartWidth = nil
                    }
            )
            .accessibilityHidden(true)
    }

    /// Pure drag math — applied per drag tick to compute the new width.
    static func apply(delta: CGFloat, start: CGFloat, range: ClosedRange<CGFloat>) -> CGFloat {
        let proposed = start + delta
        return min(max(proposed, range.lowerBound), range.upperBound)
    }

    /// Skip the setter when the incoming value equals the current value.
    /// Prevents redundant `@AppStorage` writes from triggering SwiftUI
    /// invalidation during AppKit mouse-tracking loops (#269).
    static func writeIfChanged(_ binding: Binding<CGFloat>, to value: CGFloat) {
        guard binding.wrappedValue != value else { return }
        binding.wrappedValue = value
    }
}
