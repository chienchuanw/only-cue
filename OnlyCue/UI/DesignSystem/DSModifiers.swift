import SwiftUI

extension View {

    /// A neutral panel surface — sidebar / inspector backgrounds.
    func dsPanel() -> some View {
        background(DS.Color.panel)
    }

    /// The empty-state import target — a sunken well with a dashed border.
    func dsImportWell() -> some View {
        padding(DS.Space.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DS.Color.surfaceSunken)
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    .foregroundStyle(DS.Color.border)
            )
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
    }

    /// An uppercase micro-label section header (e.g. "NEXT CUE").
    func dsSectionHeader() -> some View {
        font(DS.Text.caption)
            .tracking(DS.Text.captionTracking)
            .textCase(.uppercase)
            .foregroundStyle(DS.Color.textTertiary)
    }

    /// A 1 pt hairline divider on one edge.
    func dsHairline(edge: Edge) -> some View {
        overlay(alignment: edge.dsAlignment) {
            DS.Color.border.frame(
                width: edge.dsIsHorizontal ? nil : 1,
                height: edge.dsIsHorizontal ? 1 : nil
            )
        }
    }
}

private extension Edge {

    var dsIsHorizontal: Bool { self == .top || self == .bottom }

    var dsAlignment: Alignment {
        switch self {
        case .top: .top
        case .bottom: .bottom
        case .leading: .leading
        case .trailing: .trailing
        }
    }
}
