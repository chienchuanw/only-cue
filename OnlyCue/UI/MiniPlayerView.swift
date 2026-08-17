import SwiftUI

/// The Mini Player's compact control row (macOS, #748) — the wide horizontal
/// HUD body hosted inside the floating `NSPanel` (the panel supplies the title
/// bar / media name). Pure presentation: it renders a `MiniPlayerModel` and
/// forwards button taps to the owning document's playback seams.
///
/// Spec: `docs/superpowers/specs/2026-08-16-miniplay-design.md`. Design: Figma
/// "Mini Player (macOS)" (Cue `581:3020`, Show `583:3020`, Empty `583:3058`).
struct MiniPlayerView: View {

    let model: MiniPlayerModel
    let isPlaying: Bool
    var onPlayPause: () -> Void = {}
    var onPrevCue: () -> Void = {}
    var onNextCue: () -> Void = {}
    var onPrevSong: () -> Void = {}
    var onNextSong: () -> Void = {}
    var onGo: () -> Void = {}
    /// Absolute scrub from the progress bar — receives a 0…1 fraction (#758).
    var onSeek: (Double) -> Void = { _ in }
    /// Per-button boundary state (#753): song stops at the item-list edge, cue at
    /// the first / last cue. Default true keeps previews/tests fully enabled.
    var canPrevSong: Bool = true
    var canNextSong: Bool = true
    var canPrevCue: Bool = true
    var canNextCue: Bool = true

    var body: some View {
        VStack(spacing: DS.Space.sm) {
            HStack(spacing: DS.Space.xl) {
                transport
                timecode
                Rectangle()
                    .fill(DS.Color.border)
                    .frame(width: 1, height: 44)
                cueBlock
            }
            progressBar
        }
        .padding(.horizontal, DS.Space.lg)
        .padding(.vertical, DS.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.surface)
        .accessibilityIdentifier("miniPlayerBar")
    }

    // MARK: - Progress bar (#758)

    /// Full-width playback progress bar: a `surfaceSunken` track, a `cueIndigo`
    /// fill + knob at the playhead, and the clip length at the trailing end.
    /// Tap or drag anywhere seeks live (0…1 fraction). Dimmed + inert when empty.
    private var progressBar: some View {
        HStack(spacing: DS.Space.sm) {
            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(DS.Color.surfaceSunken).frame(height: 4)
                    Capsule()
                        .fill(DS.Color.cueIndigo)
                        .frame(width: max(0, width * model.progress), height: 4)
                    if !model.isEmpty {
                        Circle()
                            .fill(DS.Color.cueIndigo)
                            .frame(width: 11, height: 11)
                            .offset(x: width * model.progress - 5.5)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard !model.isEmpty, width > 0 else { return }
                            onSeek(min(1, max(0, value.location.x / width)))
                        }
                )
            }
            .frame(height: 11)
            Text(model.lengthLabel)
                .font(DS.Text.mono)
                .foregroundStyle(DS.Color.textTertiary)
                .fixedSize()
        }
        .opacity(model.isEmpty ? 0.5 : 1)
        .accessibilityElement()
        .accessibilityLabel("Playback progress")
        .accessibilityValue(model.lengthLabel)
        .accessibilityIdentifier("miniPlayerProgress")
    }

    // MARK: - Transport

    private var transport: some View {
        // Order mirrors the bottom transport (#753): song end-icons on the outer
        // flanks, cue double-triangles inner, play centered.
        HStack(spacing: DS.Space.sm + 2) {
            circleButton(
                "backward.end.fill",
                size: 38,
                filled: false,
                label: "Previous song",
                enabled: canPrevSong,
                action: onPrevSong
            )
            circleButton(
                "backward.fill",
                size: 38,
                filled: false,
                label: "Previous cue",
                enabled: canPrevCue,
                action: onPrevCue
            )
            circleButton(
                isPlaying ? "pause.fill" : "play.fill",
                size: 46,
                filled: true,
                label: isPlaying ? "Pause" : "Play",
                action: onPlayPause
            )
            circleButton(
                "forward.fill",
                size: 38,
                filled: false,
                label: "Next cue",
                enabled: canNextCue,
                action: onNextCue
            )
            circleButton(
                "forward.end.fill",
                size: 38,
                filled: false,
                label: "Next song",
                enabled: canNextSong,
                action: onNextSong
            )
            if model.showsGo {
                Button(action: onGo) {
                    Text("GO")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DS.Color.onCueIndigo)
                        .frame(width: 52, height: 38)
                        .background(Capsule().fill(DS.Color.cueIndigo))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Go")
            }
        }
        .disabled(model.isEmpty)
        .opacity(model.isEmpty ? 0.4 : 1)
    }

    private func circleButton(
        _ symbol: String,
        size: CGFloat,
        filled: Bool,
        label: String,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                Circle().fill(filled ? DS.Color.cueIndigo : DS.Color.surfaceSunken)
                Image(systemName: symbol)
                    .font(.system(size: size * 0.42, weight: .medium))
                    .foregroundStyle(filled ? DS.Color.onCueIndigo : DS.Color.textPrimary)
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .dsDisabledDim(!enabled)  // boundary dim/block (#753)
        .accessibilityLabel(label)
    }

    // MARK: - Readouts

    private var timecode: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.xs + 2) {
            Text(model.timecode)
                .font(DS.Text.monoHero)
                .foregroundStyle(model.isEmpty ? DS.Color.textTertiary : DS.Color.textPrimary)
            Text(model.framerateLabel)
                .font(DS.Text.small)
                .foregroundStyle(DS.Color.textTertiary)
        }
        // The timecode is the priority readout: never wrap or get squeezed by
        // the flexible cue block — that block truncates instead.
        .lineLimit(1)
        .fixedSize()
    }

    private var cueBlock: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs + 1) {
            if let current = model.currentCue {
                cueRow(current, label: "CUE", nameColor: DS.Color.textPrimary, nameFont: DS.Text.body, countdown: nil)
            } else {
                Text("No active cue")
                    .font(DS.Text.small)
                    .foregroundStyle(DS.Color.textTertiary)
            }
            if let next = model.nextCue {
                cueRow(next.cue, label: "NEXT", nameColor: DS.Color.textSecondary, nameFont: DS.Text.small, countdown: next.countdown)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func cueRow(
        _ cue: MiniPlayerModel.CueDisplay,
        label: String,
        nameColor: Color,
        nameFont: Font,
        countdown: String?
    ) -> some View {
        HStack(spacing: DS.Space.sm - 1) {
            Circle()
                .fill(cue.colorHex.flatMap { Color(hex: $0) } ?? DS.Color.textTertiary)
                .frame(width: 8, height: 8)
            Text(label + (cue.number.map { " \($0)" } ?? ""))
                .font(DS.Text.caption)
                .tracking(DS.Text.captionTracking)
                .foregroundStyle(DS.Color.textTertiary)
            Text(cue.name)
                .font(nameFont)
                .foregroundStyle(nameColor)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let countdown {
                Text(countdown)
                    .font(DS.Text.mono)
                    .foregroundStyle(DS.Color.textSecondary)
            }
        }
    }
}
