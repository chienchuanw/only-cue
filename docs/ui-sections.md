# UI sections (canonical names)

These are the stable names to use in specs, issues, PRs, design docs, and verification scripts when referring to a part of the UI. The Swift type implementing each section is in parentheses; the accessibility identifier (where one exists) is in `code` so UI tests can target it directly.

## Document Window

The top-level per-`.cuelist` window. A three-pane `NavigationSplitView` with a stacked center column.

- **Media Library Sidebar** (`ItemListPane`) — left column. The list of `MediaItem`s in the project, with drag-reorder, multi-file picker entry, the per-item TC editor row (`MediaTimecodeRow`), and drop targets for new media. Row view: `ItemRowView`. Right-click → "Edit Media…" opens the **Edit Media sheet** (`MediaEditSheet`): a hero preview strip (`MediaPreviewStrip`, ID `mediaEditPreviewStrip` — audio waveform or video poster frame via `VideoPosterGenerator`) above a read-only file-identity row (`mediaEditIdentity`), then the alternate-name, start-timecode, and per-clip LTC-mute fields.
- **Main Pane** (`DocumentView.mainPane`) — center column. Stacks the following from top to bottom:
  - **Preview Pane** (`PreviewPane`, ID `previewPane`) — video surface or audio waveform display.
    - **Video Surface** (`AVPlayerLayerView`, ID `videoPreview`) — present only when the active item is a video.
    - **Timeline Strip** — either the **Waveform View** (`WaveformContainer` / `WaveformView`, IDs `videoWaveform` / `audioWaveform`) with cue markers and the draggable **Playhead Overlay** (`PlayheadOverlay`), or the **Timeline Breakdown** (`TimelineBreakdownView`, ID `timelineBreakdownArea`) when `View → Show Timeline Breakdown` is on. The waveform is overlaid by **Cue Markers** (`CueMarkersOverlay`), the **Tempo Grid Overlay** (`TempoGridOverlay`) when enabled, and the **Waveform Zoom Magnifier** (`WaveformZoomMagnifier`) on hover. Seek surface and visual layer are split (`WaveformSeekSurface` + `WaveformPlayheadVisual`) so cue markers remain reachable to clicks.
    - **Notes Overlay** (`NotesOverlayView`) — HUD-style cue-notes overlay rendered on top of the preview when `⇧⌘N` is on.
    - **Empty Preview Placeholder** (`DocumentEmptyState`, ID `emptyPreview`) — shown when no media is loaded; clickable.
  - **LTC Strip** (`LTCStrip`) — per-clip timecode ruler with a mute button. Visible only when LTC routing is enabled and a media item is loaded (per-media LTC, epic #231).
  - **Transport Bar** (`TransportBar`) — single-line SMPTE readout (`current / total` rendered as HH:MM:SS:FF at the project framerate, ID `currentTimeReadout`), an optional `SMPTE …` readout (ID `smpteTimecode`) shown only when LTC output is enabled in Settings, and the `Next:` countdown to the upcoming cue (also SMPTE-shaped, with an optional beat-tempo countdown when the next cue carries a tempo). No visible Play/Pause or Add Cue buttons — both are wired through hidden commands; Space toggles playback and the `.addCue` shortcut adds a cue at the playhead.
- **Cue List Pane** (`CueListPane`, ID `cueListPane`) — right pane. Stacks the following:
  - **Playhead Clock** (`PlayheadClockHeader`) — pinned at the top of the pane, renders the current transport time as SMPTE timecode (HH:MM:SS:FF) at the project framerate.
  - **Cue List** — filterable list of cues for the active item with a leading color stripe and columns for Time, Number, Name, and Fade; rows are `CueRowView`. Includes the optional **BPM Column** (cue-anchored tempo). When no cues exist, shows the **Cue List Empty State**.
  - **Cue Row Interaction** — a single click in the `#`, `Name`, or `Info` column puts the caret in that field, and editing never moves the playhead. The leading colour stripe is the row's handle: clicking it selects the cue and seeks to its time. `⌘`/`⇧`-click anywhere on the row extends the selection instead of editing or seeking. Show mode locks the three columns but keeps the stripe live.
  - **Cue Row Context Menu** — right-click on a row to edit Type, Notes, or Tempo. Right-clicking a row whose field is open for editing gets AppKit's Cut/Copy/Paste field-editor menu instead — commit or `Esc` first to reach the cue menu. Each launches a modal sheet (`CueTypeSheet`, `CueNotesSheet`, `CueTempoSheet`) rather than a persistent inspector pane. Inline editing on the row itself covers Number, Name, and Fade. The standalone `CueInspectorView` was removed in favor of this row-and-modal model.

## Auxiliary surfaces

Sheets, panels, and overlays that float over (or replace) the Document Window:

- **First Launch Sheet** (`FirstLaunchSheet`) — one-time welcome.
- **Export Cues Sheet** (`ExportSheet`, via `ExportSheetPresenter`) — `File → Export Cues…` (`⇧⌘E`).
- **Timecode Settings Sheet** (`TimecodeSettingsSheet`) — project-wide framerate and start TC.
- **Type Management Sheet** (`TypeManagementSheet`) — `CuePointType` editor.
- **Notes Overlay Appearance Sheet** (`NotesOverlayPreferencesSheet`) — overlay position / font / color.
- **OSC Monitor Sheet** (`OSCMonitorView`) — `Tools → OSC Monitor…`.
- **Document Shortcut Hints** (`DocumentShortcutHints`) — on-screen cheat-sheet.

## Settings tabs

The app's Settings window (`⌘,`) hosts these tabs as siblings:

- **Audio** (`AudioSettingsView`) — master LTC enable toggle and per-channel role routing.
- **OSC** (`OSCSettingsView`) — receive-only OSC server enable + listen port.
- **Keyboard** (`KeyboardSettingsView`) — rebind any command, per-row reset, Reset All.

When adding a new UI surface, give it a canonical name here in the same PR — specs and verification scripts reference these names rather than file paths.
