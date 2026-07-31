# Spec — Rearrangeable workspace with savable presets (phase A)

**Status:** approved (grilled 2026-07-31, mockups signed off "LGTM"; sidebar spike resolved 2026-07-31)
**Area:** `area:ui`
**Implements:** `docs/architecture.md` (document window layout), ADR-023 (editor modes)
**Constrains:** #617 (window minimum width)

## Goal

A designer can adjust the document window's panes to suit how they work, and
save that arrangement as a named workspace they can return to — the way
Resolume Arena and the Adobe applications do — without the arrangement leaking
into the `.cuelist` file or the undo history.

## Phasing — this spec is phase A only

The request was for a fully rearrangeable workspace. That is being taken in
three deliberate steps, each shippable on its own:

- **A (this spec).** The existing three panes become resizable and collapsible,
  and the arrangement is savable as named presets.
- **C (later).** Panes can be torn off into separate windows for multi-display
  use.
- **B (later).** Full Resolume-style docking — arbitrary rearrangement of all
  ~12–15 regions into splits and tab groups.

The order is A → C → B and it is not arbitrary. Phase A is the smallest change
that proves a hand-rolled divider can exist in this window without breaking the
#617 minimum-width guarantee. Phase B requires a bespoke split manager; building
it before that proof is building on unverified ground.

## The obstacle this spec has to work around

`DocumentView.swift:62-86` documents #617 in full: **any NSSplitView-backed
split inside the detail column** — `.inspector` or `HSplitView` — double-counts
the sidebar into the window's minimum width (~+249pt) and holds the inspector at
its ideal rather than its minimum, pinning the populated window at 1416pt, past
the 1280pt design width. That was verified empirically by bisecting all pane
content to `Color.clear`.

The comment names the exact casualty: *"the only split feature lost is dragging
the 340–400pt divider."* Restoring that drag is precisely what this spec does —
so it must be done **without reintroducing an NSSplitView**. The divider stays a
plain SwiftUI `Divider()`; a drag gesture on it writes an explicit width into
state, which feeds the existing frame contract. No AppKit split view is
involved, so the #617 mechanism cannot re-engage.

`OnlyCueUITests/DocumentWindowMinWidthUITests.swift` (populated window ≤ 1280pt)
is the regression guard and must stay green throughout.

## Decisions (from the 2026-07-31 interview)

| # | Decision | Rationale |
|---|---|---|
| 1 | Scope = the three existing panes; no free docking, no tear-off | Smallest crossing of the #617 wall |
| 2 | Layout is stored **per `EditorMode`**; a preset is a snapshot of all three modes | Mode decides *what* is shown, workspace decides *how* it is arranged — orthogonal. Lyric mode wants a different inspector width than Cue mode |
| 3 | Storage is **app-level `UserDefaults`**, never `ProjectModel` | Layout is the person's habit, not the work's content. Storing it in the document would dirty the file, enter the undo stack, and require schema 19 |
| 4 | Named presets with full lifecycle (save-as / overwrite / rename / delete / reset), **no file import/export** | Export makes the format an external promise. Versioned JSON from day one makes adding export later purely additive |
| 5 | Widths keep today's min/max bounds (sidebar 240–320, inspector 340–400); collapse to zero allowed | Those bounds encode real layout needs of the inspector's fields. Widening them later is a two-constant change that cannot break saved presets |
| 6 | **No left/right swap** in phase A | The item list is a `NavigationSplitView` sidebar; swapping means giving up native sidebar semantics and rewriting the detail structure — disproportionate cost, and it turns #617 from one wall into several. Deferred to phase B |
| 7 | UI lives in a `View ▸ Workspace` menu; no toolbar control | Toolbar space is scarce at 1280pt (the whole of #617 is about width), and workspace switching is low-frequency |
| 8 | A preset applied to a too-narrow window is **clamped on apply, never rewritten** | Rewriting is silent data loss: the user returns to a large display and finds their workspace permanently shrunk |
| 9 | Preset application affects **the frontmost window only** | Layout is a window-level property throughout; a global apply would contradict the fact that adjustment is per-window |

## Scope

### In

1. **Draggable inspector divider.** The `Divider()` between the center pane and
   the inspector becomes a drag handle (with a resize cursor and an
   accessibility-visible affordance), constrained to 340–400pt.
2. **Collapsible inspector.** `View ▸ Hide/Show Inspector`, `⌥⌘I` (matching
   Xcode). Collapsed means width 0 and the center pane takes the space.
3. **Sidebar width and collapse.** Already native to `NavigationSplitView`
   (draggable 240–320, `⌃⌘S`); this spec captures and restores those values
   rather than reimplementing them. See the open risk below.
4. **Per-mode layout.** Each of Cue / Lyric / Show carries its own
   `PaneLayout`. Switching modes restores that mode's arrangement.
5. **Live layout memory.** The current arrangement is remembered per window and
   survives relaunch, whether or not a preset is selected. Dragging a divider
   never silently rewrites the selected preset.
6. **Named presets.** `View ▸ Workspace ▸` lists presets with the active one
   checked, plus Save Current Layout As…, Overwrite "X", Manage… (rename /
   delete), and Reset to Default. One built-in `Default` preset that cannot be
   deleted or overwritten. Selecting a preset applies immediately — there is no
   Apply button. A preset is a **snapshot, not a live binding**.
7. **New windows inherit the most recent layout**, not the factory default.

### Out

- **Free docking / tab groups / pane tear-off.** Phases B and C.
- **Left/right pane swap.** Phase B.
- **Import/export of workspace files.** Deferred; the on-disk shape is
  versioned so it stays cheap to add.
- **Any `.cuelist` schema change.** `schemaVersion` stays at 18.
- **Any change to `EditorMode` or ADR-023.** Modes are not replaced by
  workspaces; the two are orthogonal.
- **Center-pane width as a directly adjustable value.** It is whatever the
  other two leave behind — a necessary consequence of a three-column layout.
- **Widening the existing min/max bounds.**

## Behavior

### Resizing the inspector

```gherkin
Scenario: Dragging the inspector divider
  Given a document window at the default 1280pt width
  When the designer drags the divider between the editor and the inspector
  Then the inspector width follows the drag between 340 and 400 points
  And the center pane absorbs the difference
  And the window's minimum width is unchanged
```

### Collapsing the inspector

```gherkin
Scenario: Hiding the inspector
  Given the inspector is visible
  When the designer chooses View > Hide Inspector (or presses ⌥⌘I)
  Then the inspector is removed from the layout
  And the center pane occupies its space
  And pressing ⌥⌘I again restores the inspector at its previous width
```

### Layout is per mode

```gherkin
Scenario: Each editor mode remembers its own arrangement
  Given the designer widens the inspector to 400pt in Lyric mode
  When they switch to Cue mode
  Then Cue mode shows the arrangement it had before
  And switching back to Lyric mode restores the 400pt inspector
```

### Saving and switching presets

```gherkin
Scenario: Saving the current arrangement as a workspace
  Given the designer has arranged all three modes to their liking
  When they choose View > Workspace > Save Current Layout As… and name it "Focus"
  Then "Focus" appears in the Workspace menu with a checkmark
  And choosing another preset and then "Focus" again restores that arrangement
```

```gherkin
Scenario: A preset is a snapshot, not a live binding
  Given the "Focus" preset is selected
  When the designer drags the inspector divider
  Then the window shows the new width
  And "Focus" still holds the width it was saved with
  And choosing "Focus" again restores the saved width
```

### Applying a preset to a narrow window

```gherkin
Scenario: A wide-display preset applied on a laptop
  Given a preset saved with a 400pt inspector on an external display
  When it is applied to a window too narrow to honour it
  Then the layout is clamped so the center pane keeps a usable minimum
  And the inspector collapses before the center pane becomes unusable
  And the stored preset still holds 400pt
  And re-applying it on a wide window restores 400pt
```

### Multiple windows

```gherkin
Scenario: Preset application is window-scoped
  Given two documents are open in separate windows
  When the designer applies a preset in the frontmost window
  Then only that window's layout changes
  And the other window keeps its own arrangement
```

### Corrupt or missing stored layout

```gherkin
Scenario: Unreadable preferences
  Given the stored workspace data is missing or cannot be decoded
  When a document window opens
  Then it opens with the built-in Default arrangement
  And no error is surfaced to the designer
```

## Design

Follows the established app-level store pattern (`LTCRoutingStore`,
`MIDIMapStore`, `KeymapStore`): `static let shared`, `@Published`, injectable
`UserDefaults`, versioned JSON under a single key, `.default` on decode failure.

- `PaneLayout` — value type: sidebar width, sidebar collapsed, inspector width,
  inspector collapsed. `Codable`, `Equatable`.
- `WorkspaceLayout` — `[EditorMode: PaneLayout]` plus a name. `Codable`.
- `WorkspaceLayoutStore` — presets, the selected preset name, and the
  most-recent live layout. Persists to `"workspaceLayout.v1"`.
- The live per-window layout is `@SceneStorage`, so each window keeps its own
  and macOS restores it per window across relaunch. The store additionally
  holds the most recent layout so a brand-new window inherits it (decision 9's
  corollary).
- Clamping is a pure function — `PaneLayout.clamped(toAvailableWidth:)` — so
  decision 8 is unit-testable without a window.
- Design tokens: all new spacing/sizing goes through `DS`
  (`TokenConformanceTests` fails on hardcoded literals).

## Resolved risk — programmatic sidebar width (spike, 2026-07-31)

`NavigationSplitView`'s sidebar is natively draggable within
`.navigationSplitViewColumnWidth(min:ideal:max:)`, but SwiftUI offers no
documented way to read the user's dragged width back, nor to set it
imperatively when applying a preset. The single-value
`.navigationSplitViewColumnWidth(_:)` pins the width exactly.

Three candidate outcomes were spiked against a standalone app reproducing this
window's exact structure (ranged sidebar + plain-`HStack` detail). Results:

**Outcome 1 — toggle the pinned and ranged modifiers: rejected.** Pinning does
move the sidebar (240 → 300), but switching back to the ranged modifier snaps it
straight back to the *ideal*, discarding the applied width. Applying a preset
this way would visibly undo itself.

**Outcome 2 — `NSSplitView.setPosition(_:ofDividerAt:)` via an
`NSViewRepresentable` probe: adopted.** The probe walks up from a zero-size view
in the sidebar and finds the split view seven levels up (delegate
`SwiftUI.NavigationSplitViewController`). Measured behaviour:

| Check | Result |
|---|---|
| Applying a width | `setPosition(300)` → sidebar 300, SwiftUI geometry follows |
| Reading the width back | `GeometryReader` in the sidebar reports it live |
| Survives SwiftUI re-renders | yes (5 consecutive) |
| Survives inspector resize / hide / show | yes — the phase-A actions |
| Survives ordinary window resizes | yes (1400 → 1300 kept 300) |
| Effect on window minimum width | none — `contentMinSize` 1149, well under 1280 |

It writes the divider position and nothing else: no delegate is installed and no
constraint participation changes, so the #617 mechanism cannot re-engage. That
is exactly the "read/write of width alone" bar this outcome had to clear.

Two caveats carried into the plan:

- **The 8pt inset must be measured, not assumed.** The SwiftUI-reported sidebar
  width is consistently 8pt less than the split position (240↔248, 292↔300,
  257↔265). Derive the offset at runtime from the live pair; do not hardcode 8.
- **Forcing the window below its own minimum resets the divider to the ideal.**
  Only reachable programmatically — the window manager will not let a user
  resize below `minSize` — so no mitigation is planned. If it ever surfaces,
  re-asserting `setPosition` after the resize was verified to restore it.

**Outcome 3 (drop sidebar width from presets) is therefore not needed** and the
full spec scope stands.

### One manual check still outstanding

The spike could not simulate a genuine divider drag (the synthetic-event
coordinate mapping into the hosted split view was wrong, and perfecting it was
not worth the effort). Native sidebar dragging is untouched by `setPosition` —
nothing is installed that could disable it — but before Task 4 lands, confirm by
hand in the shipping app that dragging the sidebar still works and behaves the
same after a window resize.

## Acceptance criteria

- [ ] `DocumentWindowMinWidthUITests` still passes — the populated window is
      ≤ 1280pt with the draggable divider in place.
- [ ] No `NSSplitView`-backed split is introduced in the detail column; the
      divider is a plain `Divider()` with a gesture.
- [ ] The inspector resizes by drag within 340–400pt and collapses via `⌥⌘I`.
- [ ] Each `EditorMode` restores its own arrangement when selected.
- [ ] A named preset can be created, overwritten, renamed, deleted and
      re-applied; `Default` can be neither deleted nor overwritten.
- [ ] Adjusting a divider after selecting a preset does not modify the preset.
- [ ] Applying a preset in a too-narrow window clamps the applied layout and
      leaves the stored preset byte-identical.
- [ ] Applying a preset changes only the frontmost window.
- [ ] Corrupt or absent `"workspaceLayout.v1"` data yields the Default layout
      with no user-visible error.
- [ ] `ProjectModel.currentSchemaVersion` is still 18; no migration added; no
      layout change touches the undo stack or marks the document dirty.
- [ ] A new window opens with the most recently used layout.
```
