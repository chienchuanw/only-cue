import SwiftUI

enum FirstLaunchFlag {
    static let key = "didShowFirstLaunchNudge"
}

/// First-launch welcome sheet (Figma 320:2286): the OnlyCue brand hero, a
/// title + tagline, a three-row feature list (each with an icon tile and, where
/// relevant, a keyboard shortcut), a primary "Get Started" button, and a link to
/// the docs. Shown once, gated by `FirstLaunchFlag`.
struct FirstLaunchSheet: View {

    private static let docsURL = URL(string: "https://github.com/chienchuanw/only-cue#documents")

    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: DS.Space.xl) {
            heroIcon
            header
            featureList
            footer
        }
        .padding(DS.Space.xxl)
        .frame(width: 460)
        .accessibilityIdentifier("firstLaunchSheet")
    }

    private var heroIcon: some View {
        // The OnlyCue brand mark (Figma 320:2288) — the same artwork as the app
        // icon, shipped as its own asset so the hero is independent of the
        // runtime app-icon image.
        Image("BrandHero")
            .resizable()
            .interpolation(.high)
            .frame(width: 120, height: 120)
            .accessibilityHidden(true)
    }

    private var header: some View {
        VStack(spacing: DS.Space.sm) {
            Text("Welcome to OnlyCue")
                .font(.title2.weight(.semibold))
                .foregroundStyle(DS.Color.textPrimary)
            Text("Plan and run lighting cues against your media.")
                .font(DS.Text.body)
                .foregroundStyle(DS.Color.textSecondary)
        }
        .multilineTextAlignment(.center)
    }

    private var featureList: some View {
        VStack(spacing: DS.Space.md) {
            featureRow(
                glyph: "square.and.arrow.down",
                title: "Import your media",
                subtitle: "Drop an audio or video file to begin.",
                keycap: "⌘O"
            )
            featureRow(
                glyph: "mappin.and.ellipse",
                title: "Mark your cues",
                subtitle: "Press at the playhead to drop a cue.",
                keycap: "M"
            )
            featureRow(
                glyph: "dot.radiowaves.left.and.right",
                title: "Run the show",
                subtitle: "Stream SMPTE LTC and fire OSC in sync.",
                keycap: nil
            )
        }
    }

    private func featureRow(glyph: String, title: String, subtitle: String, keycap: String?) -> some View {
        HStack(spacing: DS.Space.md) {
            ZStack {
                Circle().fill(DS.Color.surfaceSunken).frame(width: 32, height: 32)
                Image(systemName: glyph)
                    .font(.system(size: 14, weight: .medium)) // off-grid: feature tile glyph
                    .foregroundStyle(DS.Color.cueIndigo)
            }
            VStack(alignment: .leading, spacing: DS.Space.xs / 2) {
                Text(title)
                    .font(DS.Text.body.weight(.semibold))
                    .foregroundStyle(DS.Color.textPrimary)
                Text(subtitle)
                    .font(DS.Text.label)
                    .foregroundStyle(DS.Color.textSecondary)
            }
            Spacer(minLength: DS.Space.sm)
            if let keycap {
                Text(keycap)
                    .font(DS.Text.monoSmall)
                    .foregroundStyle(DS.Color.textSecondary)
                    .padding(.horizontal, DS.Space.sm)
                    .padding(.vertical, DS.Space.xs / 2)
                    .background(RoundedRectangle(cornerRadius: DS.Radius.sm).fill(DS.Color.surfaceSunken))
                    .overlay(RoundedRectangle(cornerRadius: DS.Radius.sm).strokeBorder(DS.Color.border, lineWidth: 1))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        VStack(spacing: DS.Space.sm) {
            Button("Get Started") { onDismiss() }
                .buttonStyle(.borderedProminent)
                .tint(DS.Color.cueIndigo)
                .keyboardShortcut(.defaultAction)
            if let docsURL = Self.docsURL {
                Link("Read the docs on GitHub ↗", destination: docsURL)
                    .font(DS.Text.label)
                    .foregroundStyle(DS.Color.textSecondary)
            }
        }
    }
}
