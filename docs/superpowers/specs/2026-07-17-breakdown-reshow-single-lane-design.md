# Timeline breakdown — re-show a single hidden lane — design

**Date:** 2026-07-17
**Issue:** #659
**Status:** Approved

## Goal

In the Timeline Breakdown view, when one or more Type lanes are hidden, let the
user re-show a **single** hidden lane instead of only "show all at once". Today
the `+N hidden` footer button reveals every hidden lane in one step, which is
clumsy when the user hid several lanes and wants just one back.

## Decision

- Turn the hidden-lane footer button into a **Menu**:
  - one item per hidden Type (colour swatch + name) → re-shows just that Type;
  - a `Show All` item at the bottom → the existing show-all behaviour.
- The menu label keeps today's wording — `N hidden lane(s)` with the eye glyph.
- Both actions go through existing `CueCommands` (undoable, persisted in
  `.cuelist` via `CuePointType.isVisible`): `setCuePointTypeVisibility(id:to:true)`
  for a single lane, `showAllCuePointTypes` for Show All.

## Architecture

### Pure core (`OnlyCue/UI/TimelineBreakdownLayout.swift`)

- `hiddenTypes(types:) -> [CuePointType]` — the hidden Types (`!isVisible`) in
  model order. Drives the menu. `hiddenCount(types:)` becomes
  `hiddenTypes(types:).count` so the count and the menu can't diverge.

### Wiring (`OnlyCue/UI/`)

- `TimelineBreakdownView`: new `onShowType: (CuePointType.ID) -> Void` callback;
  `hiddenFooter` renders a `Menu` (items from `hiddenTypes`) instead of a single
  button. Each item calls `onShowType(type.id)`; `Show All` calls the existing
  `onShowAllTypes`.
- `PreviewPane`: wire `onShowType` to
  `CueCommands.setCuePointTypeVisibility(id:to:true, …)`.

### Compatibility

No `ProjectModel` / schema change — reuses `CuePointType.isVisible` and existing
commands. No new persistence.

## Testing

- **Unit:** `hiddenTypes(types:)` returns only hidden Types, in model order;
  empty when all visible; `hiddenCount == hiddenTypes.count`.
- **UI (XCUITest):** breakdown on, hide two lanes, open the footer menu, pick one
  Type → that lane reappears while the other stays hidden. (Menu + re-show are
  screenshot/interaction-verified.)

## Hard-rules check

No schema change, no App Sandbox, no embedded media, macOS 14.0 floor untouched.

## Out of scope

Reordering lanes; multi-select re-show; changing the per-lane hide button.
