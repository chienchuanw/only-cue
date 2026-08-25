import Foundation

/// Pure display state for the Mini Player (macOS), derived from the active
/// document's playback position + cue data. Deliberately isolated from the
/// window / SwiftUI layer so every rule (timecode formatting, current/next cue
/// selection, countdown, empty state, Show-mode GO) is unit-testable.
///
/// Spec: `docs/superpowers/specs/2026-08-16-miniplay-design.md`.
struct MiniPlayerModel: Equatable {

    /// A cue as the Mini Player shows it: formatted number, name, type colour.
    struct CueDisplay: Equatable {
        var number: String?
        var name: String
        var colorHex: String?
    }

    /// The upcoming cue plus its countdown label.
    struct NextCue: Equatable {
        var cue: CueDisplay
        var countdown: String
    }

    /// One read-only tick on the progress bar (#773): where to draw it (0…1 of
    /// the bar's width) and the cue type's colour.
    struct CueMarker: Equatable {
        var fraction: Double
        var colorHex: String
    }

    var isEmpty: Bool
    var mediaName: String
    var timecode: String
    var framerateLabel: String
    var currentCue: CueDisplay?
    var nextCue: NextCue?
    /// GO is shown only when the document is in Show mode (pure mirror).
    var showsGo: Bool
    /// Playhead position within the clip, 0…1 (0 when no media / unknown length).
    /// Drives the Mini Player progress bar (#758).
    var progress: Double
    /// The clip length as `mm:ss`, shown at the progress bar's trailing end.
    var lengthLabel: String
    /// The active clip's cues as colored ticks on the progress bar, in time
    /// order (#773). Read-only overview — never filtered by Show mode, so the
    /// Mini Player timeline always matches the main window's.
    var cueMarkers: [CueMarker]

    /// Shown as the media name when no clip is active.
    static let emptyMediaName = "No media loaded"

    /// Derive the Mini Player state. Reuses the app's own helpers so the mirror
    /// stays byte-identical to the main window: `ProjectTimecodeSettings.timecode`,
    /// `MediaItem.activeCue` / `cue(steppingFrom:)`, `TransportBar.countdownLabel`,
    /// and `FadeTime.formatNumber`.
    static func make(
        currentTime: TimeInterval,
        duration: TimeInterval = 0,
        item: MediaItem?,
        timecodeSettings: ProjectTimecodeSettings,
        cuePointTypes: [CuePointType],
        editorMode: EditorMode,
        showGoTypeID: CuePointType.ID? = nil
    ) -> Self {
        let rate = timecodeSettings.framerate
        let showsGo = editorMode == .show
        // The Show-mode type filter applies to GO + stepping only in Show mode,
        // exactly as the main window does (#657).
        let filterTypeID = showsGo ? showGoTypeID : nil

        guard let item else {
            return Self(
                isEmpty: true,
                mediaName: emptyMediaName,
                timecode: Timecode(frameCount: 0, rate: rate).displayString,
                framerateLabel: rate.shortDisplayName,
                currentCue: nil,
                nextCue: nil,
                showsGo: showsGo,
                progress: 0,
                lengthLabel: clockLabel(0),
                cueMarkers: []
            )
        }

        func display(_ cue: Cue) -> CueDisplay {
            CueDisplay(
                number: cue.cueNumber.map(FadeTime.formatNumber),
                name: cue.name,
                colorHex: cuePointTypes.first { $0.id == cue.typeID }?.colorHex
            )
        }

        let current = item.activeCue(at: currentTime, typeID: filterTypeID).map(display)

        let next = item.cue(steppingFrom: currentTime, direction: .next, typeID: filterTypeID).map { upcoming in
            NextCue(
                cue: display(upcoming),
                countdown: TransportBar.countdownLabel(
                    mode: .time,
                    interval: max(0, upcoming.time - currentTime),
                    activeTempo: nil,
                    rate: rate
                )
            )
        }

        return Self(
            isEmpty: false,
            mediaName: item.resolvedName,
            timecode: timecodeSettings.timecode(atPlaybackSeconds: currentTime, forItem: item).displayString,
            framerateLabel: rate.shortDisplayName,
            currentCue: current,
            nextCue: next,
            showsGo: showsGo,
            progress: progressFraction(currentTime, duration),
            lengthLabel: clockLabel(duration),
            cueMarkers: cueMarkers(item.cues, duration: duration, cuePointTypes: cuePointTypes)
        )
    }

    /// The progress bar's tick layer (#773). A cue earns a tick only when its
    /// type resolves and is visible, and when its time actually falls inside the
    /// clip — out-of-range times are dropped rather than clamped, which would
    /// pile a fake thick tick onto the bar's edge. Coincident cues are kept as
    /// separate ticks: a dense stretch is *meant* to read as a solid block.
    static func cueMarkers(
        _ cues: [Cue],
        duration: TimeInterval,
        cuePointTypes: [CuePointType]
    ) -> [CueMarker] {
        guard duration > 0 else { return [] }
        return cues
            .filter { (0...duration).contains($0.time) }
            .sorted { $0.time < $1.time }
            .compactMap { cue in
                guard let type = cuePointTypes.first(where: { $0.id == cue.typeID }), type.isVisible else {
                    return nil
                }
                return CueMarker(fraction: cue.time / duration, colorHex: type.colorHex)
            }
    }

    /// Playhead position as a 0…1 fraction, clamped; 0 when the length is
    /// unknown (`duration <= 0`, e.g. before the asset loads).
    static func progressFraction(_ currentTime: TimeInterval, _ duration: TimeInterval) -> Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, currentTime / duration))
    }

    /// Formats a duration as `mm:ss` (rounded). Clips are short, so hours are
    /// folded into the minutes field.
    static func clockLabel(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
