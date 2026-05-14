import AppKit
import SwiftUI

/// A 6pt-wide invisible drag region for resizing a column's trailing edge.
/// Cursor flips to `resizeLeftRight` on hover; dragging writes the clamped
/// width back through the supplied binding.
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
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if dragStartWidth == nil { dragStartWidth = width }
                        let start = dragStartWidth ?? width
                        width = Self.apply(delta: value.translation.width, start: start, range: range)
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
}
