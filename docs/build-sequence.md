# Build Sequence

A **walking-skeleton** sequence: every step ends with the app still launchable and demonstrably better than the last. Pick up at any step if a detour pulls us off the path.

## Order

| # | Step | Done when |
|---|---|---|
| 1 | **Skeleton** | Xcode project compiles. `DocumentGroup` opens an empty doc. `.cuelist` UTType registered in `Info.plist`. `ProjectModel` Codable round-trip test passes. |
| 2 | **Player core** | `PlayerEngine` plays/pauses/seeks a hardcoded asset. `TransportBar` UI hooked up. `currentTime` updates drive a label. |
| 3 | **Media import** | `⌘O` and drag-drop accept supported audio + video. Bookmark created and stored in `MediaReference`. Player loads the imported asset. |
| 4 | **Video preview pane** | `AVPlayerLayer` wrapped via `NSViewRepresentable`. `.mp4` and `.mov` show picture stacked above the step-5 waveform strip; transport drives video. |
| 5 | **Waveform** | `WaveformGenerator` produces peak arrays asynchronously. `WaveformView` renders peaks via `Canvas`. Peak cache hits on second open. |
| 6 | **Cue list pane (read-only)** | Right-side pane shows cues from `ProjectModel.cues`. Empty state when none. |
| 7 | **Add / edit / delete cues** | `M` adds at playhead. Inline rename, color picker, time edit, delete. All routed through `CueCommands` with `UndoManager`. |
| 8 | **Cue markers on waveform** | Markers drawn at correct x-positions. Drag to retime. Click to seek. |
| 9 | **Polish** | Empty states. Missing-media alert with "Relink…". App icon. Default keyboard shortcuts. About box. |
| 10 | **Distribution** | Developer ID signing. Notarization. DMG built via `create-dmg`. Manual install on a clean Mac succeeds. |

## Detour rules

When a step takes longer than expected, prefer this order:

1. **Reduce scope inside the step** before skipping it. (e.g. waveform: ship mono, monochrome, no zoom for v1.)
2. **Mock the dependency**, not the feature. (e.g. ship a fake `WaveformGenerator` returning sine peaks while the real one is debugged.)
3. **Skip and log a TODO** only if the step is non-blocking for the next one.

The dependency chain:

```
1 → 2 → 3 → (4, 5 in parallel) → 6 → 7 → 8 → 9 → 10
```

Steps 4 and 5 are independent and can be split across two people.

## Definition of done for the MVP

The end-to-end script in [`verification.md`](verification.md) passes on a fresh user account with a freshly built DMG installed.
