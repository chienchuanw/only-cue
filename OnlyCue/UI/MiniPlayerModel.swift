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
                lengthLabel: clockLabel(0)
            )
        }

        func colorHex(_ typeID: CuePointType.ID) -> String? {
            cuePointTypes.first { $0.id == typeID }?.colorHex
        }
        func display(_ cue: Cue) -> CueDisplay {
            CueDisplay(
                number: cue.cueNumber.map(FadeTime.formatNumber),
                name: cue.name,
                colorHex: colorHex(cue.typeID)
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
            lengthLabel: clockLabel(duration)
        )
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
