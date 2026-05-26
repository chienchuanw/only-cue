import SwiftUI

/// Reusable SwiftUI styles that bake `DS.Color.cueIndigo` into primitives
/// whose system defaults would otherwise pick up `controlAccent`. Companion
/// to `DS.Color` — see the `cueIndigo` doc-comment in `DSColor.swift` for
/// rollout guidance.
///
/// The styles intentionally stay minimal: they only override what's needed
/// to bind the brand color through. Layout, sizing, and shape are left to
/// the default style, so adopting one is a one-line change at the callsite
/// (`.toggleStyle(IndigoToggleStyle())`, `.buttonStyle(IndigoPrimaryButtonStyle())`).

extension DS {

    /// `ToggleStyle` whose on-state pill uses `DS.Color.cueIndigo` instead
    /// of `controlAccent`. Visual shape mirrors the macOS default — a
    /// rounded capsule with a white knob — so swapping to this style does
    /// not move the toggle visually except for the on-fill color.
    struct IndigoToggleStyle: ToggleStyle {
        func makeBody(configuration: Configuration) -> some View {
            HStack {
                configuration.label
                Spacer()
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(configuration.isOn ? DS.Color.cueIndigo : DS.Color.borderStrong)
                        .frame(width: 40, height: 22)
                    Circle()
                        .fill(.white)
                        .shadow(radius: 0.5, y: 0.5)
                        .frame(width: 18, height: 18)
                        .padding(.horizontal, 2)
                }
                .animation(.easeInOut(duration: 0.15), value: configuration.isOn)
                .onTapGesture { configuration.isOn.toggle() }
                .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
            }
        }
    }

    /// `ButtonStyle` for primary-action buttons in sheets and dialogs
    /// (Done / Save / Export… / Confirm). Renders a rounded capsule with
    /// a `cueIndigo` fill and `onCueIndigo` foreground, sized to match
    /// the macOS bordered-prominent height.
    struct IndigoPrimaryButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DS.Color.onCueIndigo)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(DS.Color.cueIndigo)
                        .opacity(configuration.isPressed ? 0.85 : 1)
                )
                .opacity(configuration.role == .destructive ? 0.6 : 1)
        }
    }
}
