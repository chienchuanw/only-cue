# Show mode — GO filtered by cue type — design

**Date:** 2026-07-17
**Issue:** #657
**Status:** Approved (grilling)

## Goal

In Show mode, let a show caller pick a single cue **type**; then GO / prev-cue /
next-cue / the current-cue highlight / the notes overlay all only walk or show
cues of that type, and the cue list dims every cue of other types. "All" keeps
today's behaviour (walk everything).

## Decisions (locked with the user)

- **Single type + "All"** (nil = All). One selected `CuePointType.ID?` per window.
- **Filter scope — all only in Show mode:**
  - GO (button / Return / OSC `/onlycue/cue/go`) walks the next cue of the
    selected type.
  - Prev / next cue (transport / keyboard / OSC `/cue/next` `/cue/prev`) walk the
    selected type only.
  - Cue list: rows of other types are **dimmed** (lowered opacity, still visible).
  - Current-cue highlight + notes overlay: the current cue is the latest cue of
    the selected type at/before the playhead.
- **Picker UI:** a dropdown in the **lower part of `CueListPane`**, shown **only
  in Show mode** — options are **All + each cue type** (colour dot + name).
- **Persistence:** `@SceneStorage("onlycue.showGoTypeID")` (per-window, like
  `editorMode`), storing the type UUID string ("" = All).
- **Edges:** no cue of the selected type → GO/step no-op; a deleted type → the
  filter falls back to All (a stored id that matches no type reads as All);
  cue / lyric modes are untouched (no picker, no dimming, step walks all cues).

## Architecture

Pure filtering added as an **optional `typeID` parameter** (nil = all, the
current behaviour) to the existing pure cue queries — so every existing caller
and test keeps working unchanged; only Show mode passes a non-nil id.

### Pure core (`OnlyCue/Document/`)

- `MediaItem.cue(steppingFrom:direction:typeID:)` — `typeID: CuePointType.ID? =
  nil`; when non-nil, only cues whose `typeID` matches are considered.
- `MediaItem.showGoDecision(from:typeID:)` — threads the id into stepping.
- `MediaItem.activeCue(at:typeID:)` — `typeID: … = nil`; when non-nil, the latest
  matching cue at/before the time.
- A stored id matching no current type filters to an empty set → treated as All
  by the caller (DocumentView resolves "" / unknown → nil).

### Wiring (`OnlyCue/UI/`)

- `DocumentView`: `@SceneStorage("onlycue.showGoTypeID") private var
  showGoTypeIDRaw = ""`. A computed `showGoTypeID: CuePointType.ID?` that is nil
  unless `editorMode == .show` **and** the raw string parses to a UUID that
  matches a current type. `performGo` / `stepPlayhead` pass it.
- `OSCServerHost`: already receives `editorMode`; also receive the resolved
  `showGoTypeID` so `step` / `goNextCueAndPlay` filter identically.
- `PreviewPane`: the notes overlay's `activeCue(at:)` passes the id.
- `CueListPane`: current-cue highlight uses the filtered `activeCue`; a Show-mode
  type dropdown in the lower area (`All` + types with colour dots); each cue row
  is dimmed when a type is selected and the row's `typeID` differs.

### Compatibility

Filter is transient window state — no `.cuelist` / `ProjectModel` schema change.
`nil` typeID everywhere preserves current behaviour, so existing tests stand.

## Testing

- **Unit:** `cue(steppingFrom:direction:typeID:)` walks only the given type
  (skips others), nil walks all; `showGoDecision(from:typeID:)` filters;
  `activeCue(at:typeID:)` returns the latest matching cue, nil = all. Existing
  stepping/activeCue/showGoDecision tests remain (they call the nil default).
- **UI (XCUITest):** Show mode, seed cues of ≥2 types, select a type in the
  picker → GO lands on that type's next cue; other-type rows are dimmed. (Movement
  covered by unit tests; the picker + dim are run/screenshot-verified.)
- **Not unit-tested:** the dropdown + opacity — run-verified.

## Hard-rules check

No `ProjectModel` schema change (transient `@SceneStorage`). No App Sandbox. No
embedded media. macOS 14.0 floor untouched.

## Out of scope (next PR)

Re-showing a single hidden breakdown lane (the "all hidden → only show-all" UX).
Multi-type GO selection.
</content>
