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

    /// Disables the system selection highlight on the enclosing `NSTableView`
    /// so only the custom row background shows (#679). Returns the table it
    /// styled, or nil when there is none above `view`.
    @discardableResult
    @MainActor
    static func disableSystemHighlight(from view: NSView) -> NSTableView? {
        guard let table = enclosingTable(of: view) else { return nil }
        table.selectionHighlightStyle = .none
        return table
    }

    /// Makes the enclosing `NSTableView` refuse first responder, so the table
    /// never receives `keyDown` and its built-in type-select can't swallow digit
    /// cue hotkeys (#750). Mouse-click row selection is unaffected; keyboard row
    /// navigation and ⌫-to-delete are intentionally given up on this list (media
    /// selection is mouse-first, and Remove stays on the row context menu).
    /// Returns the table it changed, or nil when there is none above `view`.
    @discardableResult
    @MainActor
    static func disableTypeSelect(from view: NSView) -> NSTableView? {
        guard let table = enclosingTable(of: view) else { return nil }
        table.refusesFirstResponder = true
        return table
    }

    /// Walks up the superview chain from `view` to the nearest enclosing
    /// `NSTableView`. Walking *up* from a per-row probe targets that row's own
    /// list — both panes share one window, so a window-wide search could reach
    /// the wrong table.
    @MainActor
    private static func enclosingTable(of view: NSView) -> NSTableView? {
        var current: NSView? = view
        while let node = current {
            if let table = node as? NSTableView { return table }
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
    /// When true, the probe also makes the enclosing table refuse first
    /// responder to kill type-select (#750). Media lists opt in; the cue list
    /// keeps only the highlight suppression.
    var disablesTypeSelect = false

    func apply() {
        TableSelectionHighlightStyler.disableSystemHighlight(from: self)
        if disablesTypeSelect {
            TableSelectionHighlightStyler.disableTypeSelect(from: self)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        apply()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        apply()
    }
}

private struct PlainListSelectionProbe: NSViewRepresentable {
    var disableTypeSelect = false

    func makeNSView(context: Context) -> NSView {
        let view = SelectionHighlightProbeView()
        view.disablesTypeSelect = disableTypeSelect
        view.setAccessibilityHidden(true)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let probe = nsView as? SelectionHighlightProbeView else { return }
        probe.disablesTypeSelect = disableTypeSelect
        probe.apply()
    }
}

extension View {
    /// Strips the macOS system selection highlight from the enclosing `List`'s
    /// `NSTableView` so only the custom row background shows (#679). Apply to a
    /// row inside a `List(selection:)`.
    ///
    /// Pass `disableTypeSelect: true` to also make the table refuse first
    /// responder, killing its built-in type-select so digit cue hotkeys aren't
    /// swallowed by the media list (#750).
    func plainListSelectionHighlight(disableTypeSelect: Bool = false) -> some View {
        background(PlainListSelectionProbe(disableTypeSelect: disableTypeSelect).frame(width: 0, height: 0))
    }
}
