# grandMA2 push — split the live sheet from the plugin config (#688) — design

**Extends:** #683 / #686 (v0.16.0). **Status:** approved (brainstormed with owner).

## Problem

The **Send to grandMA2…** live push (Approach A) builds a sequence of per-cue
`Trig=Timecode` cues — it never creates a timecode-pool object — yet its sheet still
asks for a **Timecode slot** and a **Go/Goto command**. Those are dead controls on the
live sheet: `MA2CommandPlanner` uses neither. They only matter to **Export grandMA2
plugin…** (Approach C), which builds a real timecode object — but C has no config sheet
today (it exports straight from the saved target).

(Confirmed: executor assignment is *not* a dead control — a sequence must live on an
executor to be run/chased; owner chose to keep the auto-assign. Approach A is retained
because it is the only *live* route to an onPC that has no FTP and whose filesystem is
unreachable for a plugin file.)

## Design

- **`MA2PushSheet` (A) — trim.** Remove the Timecode-slot `TextField` and the TC-command
  `Picker` from the target card. Keep sequence name, sequence slot, executor, cue-type
  filter. The `timecodeSlot` / `timecodeCommand` `@State` stay (seeded from the saved
  target, still written into `currentTarget`) so C's persisted values survive edits made
  on the live sheet. The push path is unchanged (it already ignores both).

- **`MA2PluginExportSheet` (C) — new config sheet.** A sheet modeled on the push sheet but
  for a file export: full target card (sequence name, sequence slot, executor, **timecode
  slot**, **TC command**, cue-type filter) + a pre-flight card + an **Export…** button.
  Export runs `MA2PushRequestBuilder.pluginOutcome`, and on `.ready` persists the target
  (`CueCommands.setMA2PushTarget`) and writes the bundle via `NSSavePanel` +
  `MA2PluginWriter`; on `.blocked` shows the pre-flight issues in-sheet. No host / password
  / telnet / progress list (it never connects).

- **`MA2PluginExportPresenter` — rewire.** Instead of exporting immediately on
  `.exportMA2PluginRequested`, resolve the item and present `MA2PluginExportSheet` via
  `.sheet(item:)` (mirroring `MA2PushSheetPresenter`). The direct-export + alert logic
  moves into the sheet.

Both sheets edit and persist the **same** per-clip `MA2PushTarget`, so sequence slot /
executor / name stay consistent across the two flows; only C additionally edits the
timecode slot + command.

## Components

| Unit | Change |
| --- | --- |
| `MA2PushSheet` | remove 2 controls from `targetCard`; keep state + `currentTarget` |
| `MA2PluginExportSheet` (new) | config + pre-flight + Export→save-panel |
| `MA2PluginExportPresenter` | present the sheet instead of exporting inline |

## Testing

Logic layer (`commandOutcome` ignores TC fields; `pluginOutcome` uses them) is unchanged
and already unit-tested — no new pure logic here. Verification is: full unit suite stays
green, app builds, `swiftlint --strict` clean. (Consistent with the project's existing
"MA2 flows are pure-logic-tested; sheets have no XCUITest" convention.)

## Out of scope

Extracting a shared target-fields component (the two sheets differ enough — push has
host/password/progress, export has a save panel — that a shared component is not worth the
coupling now). Any change to the push/plugin *logic*.

## Conventions

Conversation zh-TW; code/commits/PRs English. No `Co-Authored-By`. No direct `ProjectModel`
mutation (via `CueCommands`). `swiftlint --strict` clean. macOS ≥ 14.
