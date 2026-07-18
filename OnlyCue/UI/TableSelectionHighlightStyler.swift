import SwiftUI

/// Removes the macOS system selection highlight (the emphasized blue / reverse-
/// video fill) from a SwiftUI `List`'s backing `NSTableView`, so only the
/// custom `.listRowBackground` shows (#679). `List(selection:)` and all its
/// behavior — keyboard navigation, shift/cmd multi-select, the focus ring — are
/// untouched; only the drawing changes.
///
/// SwiftUI exposes no API for this, hence the AppKit introspection. It is kept
/// deliberately small and re-applied on every view update so a table rebuild
/// can't silently restore the blue.
enum TableSelectionHighlightStyler {

    /// Walks up the superview chain from `view` to the nearest enclosing
    /// `NSTableView` and disables its system selection highlight. Returns the
    /// table it styled, or nil when there is none above `view`. Walking *up*
    /// from a per-row probe targets that row's own list — both panes share one
    /// window, so a window-wide search could style the wrong table.
    @discardableResult
    @MainActor
    static func disableSystemHighlight(from view: NSView) -> NSTableView? {
        var current: NSView? = view
        while let node = current {
            if let table = node as? NSTableView {
                table.selectionHighlightStyle = .none
                return table
            }
            current = node.superview
        }
        return nil
    }
}

/// Zero-size AppKit probe hosted behind a `List` row that disables the
/// enclosing table's system selection highlight (#679). It re-applies whenever
/// it is actually spliced into the view tree (`viewDidMoveToWindow` /
/// `viewDidMoveToSuperview`) — not on a hopeful single async hop — so the table
/// is reachable by the time the walk runs, and again on every SwiftUI update in
/// case a table rebuild restored the blue.
private final class SelectionHighlightProbeView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        TableSelectionHighlightStyler.disableSystemHighlight(from: self)
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        TableSelectionHighlightStyler.disableSystemHighlight(from: self)
    }
}

private struct PlainListSelectionProbe: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = SelectionHighlightProbeView()
        view.setAccessibilityHidden(true)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        TableSelectionHighlightStyler.disableSystemHighlight(from: nsView)
    }
}

extension View {
    /// Strips the macOS system selection highlight from the enclosing `List`'s
    /// `NSTableView` so only the custom row background shows (#679). Apply to a
    /// row inside a `List(selection:)`.
    func plainListSelectionHighlight() -> some View {
        background(PlainListSelectionProbe().frame(width: 0, height: 0))
    }
}
