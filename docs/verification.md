# Verification

How we know the MVP works. Two layers: an end-to-end manual script (the source of truth) and a small automated suite that prevents regressions in the parts that are cheap to test.

## Manual end-to-end script

Run on a clean user account with a freshly installed DMG. Use bundled fixtures `sample.mp3` and `clip.mp4`.

1. Launch the app → a new untitled document opens with empty preview and empty cue list.
2. Drag `sample.mp3` onto the window → waveform appears, transport becomes active, time readout shows `00:03:04.000` (= duration).
3. Press space → audio plays, playhead moves on the waveform, time readout advances.
4. Press `M` three times at different points → 3 cues appear in the list and as markers on the waveform.
5. Double-click cue #2 name → rename to `Chorus` → press enter → list updates.
6. Drag cue #2's waveform marker → its time field updates live; release → list reflects the new time.
7. Click cue #1 in the list → playhead jumps to its time; pressing space resumes from there.
8. `⌘Z` → last edit undone. `⌘⇧Z` → redone. Repeat across mixed edits (rename + retime + delete).
9. `⌘S` → save as `Show.cuelist` to Desktop. Quit the app.
10. Re-launch → File → Open Recent → `Show.cuelist` → media reloads via bookmark, all cues intact, time fields match.
11. Repeat steps 2–10 with `clip.mp4` to validate the video path (preview pane shows picture instead of waveform).
12. Move `sample.mp3` to a new folder, then reopen `Show.cuelist` → app surfaces a "Relink media…" alert; relinking restores playback.

If any step fails, the MVP is not done.

## Automated suite

Cheap, fast tests that catch the regressions that humans miss.

### Unit (XCTest)

- `ProjectModelTests` — JSON round-trip preserves all fields, sorted-key output is stable.
- `CueTests` — color-hex validation, time bounds vs media duration.
- `CueCommandsTests` — add / delete / rename / retime each register inverse undo; redo restores state exactly.
- `WaveformGeneratorTests` — peak array length matches requested resolution; deterministic for the same input.
- `BookmarksTests` — round-trip create → encode → decode → resolve on a temp file.

### UI smoke (XCUITest)

One scripted flow:

1. Launch fresh document.
2. Programmatically open a bundled fixture media file.
3. Send `M` keystroke twice.
4. Assert two rows in the cue list.
5. Save to a temp URL.
6. Close, reopen the saved doc.
7. Assert the same two rows are still present.

We deliberately keep UI tests minimal — they are slow and flaky. Coverage lives in unit tests.

## Performance budgets

Not formal perf tests, but anything outside these budgets is a bug to investigate, not ship around.

| Action | Budget |
|---|---|
| Open `.cuelist` (10 KB JSON, media on local SSD) | < 250 ms to interactive |
| Waveform render for 5-min audio | < 1 s after load (cache miss); instant (cache hit) |
| Add cue at playhead | < 16 ms (one frame) |
| Save document | < 50 ms |

## Distribution sanity check

Before tagging a release:

- `codesign --verify --deep --strict --verbose=2 OnlyCue.app` clean. (Passes for both ad-hoc and Developer ID signatures.)
- `spctl --assess --type execute OnlyCue.app` outcome depends on `RELEASE_MODE`:
    - **Unsigned (free-tier)**: returns "rejected: Unnotarized Developer ID" or similar — expected. End users use right-click → Open as documented in the install instructions.
    - **Signed**: must accept. If it rejects after stapling, re-staple and try again.
- DMG opens, drag-to-Applications works.
- First launch on a Mac that has never seen the app:
    - **Unsigned**: shows the standard "developer cannot be verified" Gatekeeper prompt; right-click → Open clears it; the app launches and the system remembers the override. Must **not** show "OnlyCue is damaged and can't be opened" — that indicates the ad-hoc signature didn't take.
    - **Signed**: launches silently with no Gatekeeper prompt.
