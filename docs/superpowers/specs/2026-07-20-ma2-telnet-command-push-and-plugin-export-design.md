# grandMA2 push — telnet-command mode (A) + plugin export (C) — design

**Spec section implemented:** extends `docs/` grandMA2 integration (#683 / PR #684).
**Supersedes:** the XML-over-FTP live-push path of #683 for the *live* case.
**Status:** design, pending approval. Real-rig validated on grandMA2 onPC `2.0.0.193`
(2026-07-20). Do not merge / flip PR #684 to ready without the owner's go-ahead.

## Problem

The shipped #683 push uploads two XML files over the console's FTP server, then
imports them over telnet. Real-rig validation found the blocking facts:

- **grandMA2 onPC has no FTP server** (port 21 closed). The FTP upload — the first
  two steps of every push — cannot run against onPC, which is the owner's primary
  development console. Real full-size consoles do have FTP; onPC does not.
- **A timecode-pool object's events are not buildable over telnet.** `Store Timecode
  N Event …` / `… At … Cue …` are silently ignored (delete-probe read-back confirms
  nothing is created); `Assign Sequence … At Timecode …` → `Error #72`. This is why
  #683 used XML import for the timecode show — and why the FTP dependency is
  structural, not incidental, in the current design.

So the current design cannot deliver the feature on onPC at all.

## Rig findings that drive the design (grandMA2 onPC v3.9, telnet 30000)

1. Login `administrator` / `admin`; success text `Logged in as User 'administrator'`.
2. Everything the sequence half needs **is** buildable over pure telnet commands:
   - `Store Sequence <slot> Cue <n> "<name>" /nc` creates a content-empty cue
     (empty programmer is fine). Fractional numbers work directly (`Cue 2.001`).
   - `Assign Sequence <slot> Cue <n> /Trig=Timecode` and
     `Assign Sequence <slot> Cue <n> /TrigTime=<seconds>` are accepted; `/fade=` /
     `/outfade=` too. `Label`, `Assign … At Exec <p>.<e>` too.
   - Delete-probe read-back proved the cues (incl. `1.15`, `2.001`) really exist.
3. **You do not set a timecode slot.** `Assign Sequence … /TimecodeSlot=N` caps at
   `N ≤ 7` (`Error #9`), but grandMA2 defaults a sequence's timecode slot to
   **"link selected"**, so its `Trig=Timecode` cues chase whichever TC slot is
   selected/running. Owner confirmed this is the normal setup — omit it.
4. **End-to-end playback verified on the onPC GUI:** a sequence of `Trig=Timecode` /
   `TrigTime` cues, driven by a running internal timecode, stepped its executor
   through the cues at their exact TrigTimes.
5. The reference tool **CuePoints** (plugins the owner shared) does exactly this:
   its "cue trigger" export is a `.lua` plugin of `Store Sequence … Cue …` +
   `Assign … /Trig=Timecode` + `Assign … /TrigTime=<decimal seconds>`; its "TC
   object" export additionally writes a timecode XML to the console's local
   `importexport` via Lua `io.open` and `Import … At Timecode N`. That TC XML is
   structurally identical to OnlyCue's `MA2TimecodeXMLGenerator` output —
   independently confirming our XML schema and `Import "<base>" At Timecode <n>`
   syntax are correct.

## Decision

Ship **two** delivery mechanisms, sharing the cue → MA2 mapping:

- **A — "Send to grandMA2…" (live, telnet, no files).** Build the sequence with
  per-cue `Trig=Timecode` / `TrigTime` over telnet 30000. No FTP, no XML, no
  timecode-pool object. Works on onPC **and** real consoles. This replaces the
  live push's XML+FTP transport.
- **C — "Export grandMA2 plugin…" (file).** Generate a self-contained `.lua`
  plugin (+ its `.xml` wrapper) that, when imported and run on any console, builds
  the sequence and writes+imports a real timecode-pool object locally (the
  CuePoints "TC object" pattern). No FTP (the plugin writes to the console's own
  disk). The user saves the plugin and hand-carries / imports it. This preserves
  the "real Timecode show object" outcome for venues that want it, and reuses the
  existing XML generators verbatim.

The A/C split is a consequence of transport, not preference: a live remote push
cannot create a timecode-pool object (finding #2), so the live path uses per-cue
triggers; the plugin runs on the console, so it can. Both satisfy "media time →
cue fires."

## Approach A — telnet-command push

### Command plan (per push), all validated on the rig

```
Delete Sequence <seq> /nc                 # idempotent pre-clean (empty slot → WARNING, not Error)
# for each cue, in cue-number order:
Store Sequence <seq> Cue <num> "<name>" /nc
Assign Sequence <seq> Cue <num> /Trig=Timecode
Assign Sequence <seq> Cue <num> /TrigTime=<abs seconds>
Assign Sequence <seq> Cue <num> /fade=<s>          # only when fadeIn > 0
Assign Sequence <seq> Cue <num> /outfade=<s>       # only when fadeOut > 0
Label Sequence <seq> "<sequenceName>"
Assign Sequence <seq> At Exec <page>.<exec>
```

- **No** `Delete Timecode`, **no** `cd`/`Import`, **no** `/TimecodeSlot`, **no**
  timecode-pool object. The executor keeps the sequence; the operator selects the
  TC slot that receives OnlyCue's LTC and the cues chase it.
- Cue number: use the OnlyCue `cueNumber` directly, formatted to at most three
  decimals via the existing thousandths rounding (reuse `MA2CueNumber` →
  `"<number>.<zero-padded sub_number>"`, or `<number>` when sub is 0). Preflight
  (unique, non-nil cue numbers) is unchanged and still runs first.
- Name quoting reuses `MA2PushPlanner.commandQuotable` (strip embedded `"`).

### TrigTime encoding — the four generator formats

grandMA2's timecode generator has exactly four formats: **`1/100 seconds`, `30 fps`,
`25 fps`, `24 fps`** (no 29.97DF format). `TrigTime` is entered against the slot's
format, so the value must be built to land on the intended instant.

Decision: **emit `TrigTime` as absolute decimal seconds on the project's frame
grid**, reusing the frame math the current timecode generator already uses:

```
absFrames   = startTimecodeFrames + Int((cue.time * fps).rounded())   // fps = framerate.framesPerSecond
trigSeconds = Double(absFrames) / Double(fps)                          // exact frame boundary, in seconds
TrigTime    = trigSeconds, trimmed to a stable decimal string          // e.g. 154.133333
```

- Decimal seconds is the form validated on the rig (`/TrigTime=5`, `/TrigTime=154.1333`);
  the console quantizes to its slot format. Emitting on the project frame grid means
  the value is an exact frame at the project fps.
- **fps30drop:** `framesPerSecond` is 30. Because we emit *seconds* (not a physical
  frame count under a mislabeled non-drop format), the old "physical frames under a
  `30 FPS` label" hazard in `MA2TimecodeXMLGenerator` **does not exist on path A**.
  Frame-accurate DF landing still depends on the console's slot format matching
  OnlyCue's LTC; using the `1/100 seconds` generator format sidesteps frame/drop
  entirely. This is an operator-alignment note + a real-LTC verification item, not a
  baked-in encoding bug.

### Reuse / removal (path A)

- **Reused unchanged:** `MA2PushPreflight`, `MA2PushTransport` / `MA2TelnetClient`,
  `MA2ConnectionSettings` / `MA2Keychain`, `CueCommands.setMA2PushTarget`,
  `MA2PushTarget` fields `sequenceSlot` / `executorPage` / `executorNumber` /
  `includedTypeIDs`, the push sheet's progress UI.
- **Not used by A** (still used by C): `timecodeSlot`, `timecodeCommand`.
- **Removed from the live path:** the two FTP upload steps and `MA2Uploading` /
  `MA2CurlUploader` / `MA2FTPUploader` (moves to C's reuse or is retired from live).
- **New:** an `MA2CommandPlanner` producing the command list above; a `TrigTime`
  encoder; `MA2PushRunner` gains a commands-only path (connect → login → commands,
  no uploads).

### Idempotent re-push

`Delete Sequence <seq> /nc` first (validated: empty slot → `WARNING, NO OBJECTS
FOUND FOR DELETE`, which is not an `Error #`, so the stop-on-first-error runner does
not false-trip). Re-push rebuilds the same slot → exactly one copy.

## Approach C — plugin export

Generate two files (mirroring the shared `cuepoints.xml` + `CuePoints_PLUGIN.lua`
shape):

- `<name>.xml` — `<MA><Plugin index="0" name="…" luafile="<name>_PLUGIN.lua"/></MA>`.
- `<name>_PLUGIN.lua` — a `gma.cmd`/`io.open` script that:
  1. `Delete Sequence <seq> /nc` then `CMD('Store Sequence …')` builds the sequence
     (reusing A's command list — same `Store`/`Assign`/`Label` strings), **or**
     writes+imports the sequence XML (reusing `MA2SequenceXMLGenerator`).
  2. Writes the timecode XML from `MA2TimecodeXMLGenerator` to
     `gma.show.getvar('PATH')/importexport/<file>.xml` via `io.open`, then
     `CMD('Import "<base>" At Timecode <tc>')`, `gma.sleep(0.5)`, `os.remove(...)`.
- Delivered via `NSSavePanel` (a folder/zip of the two files). No live connection,
  no FTP. Reuses `MA2PushTarget` in full (incl. `timecodeSlot`, `timecodeCommand`),
  `MA2SequenceXMLGenerator`, `MA2TimecodeXMLGenerator`, `MA2PushPlanner` payloads.
- **New:** `MA2PluginGenerator` (pure string builder, fully unit-testable against a
  golden `.lua`), a save-panel action, and a File-menu / right-click entry
  "Export grandMA2 plugin…".

## Data model / schema

No schema change. `MA2PushTarget` (schema **v17**) already carries every field both
paths need; A simply ignores `timecodeSlot` / `timecodeCommand`. No new persisted
fields, so `currentSchemaVersion` stays 17 and no migration is added. (If a future
"link-selected vs pinned slot" toggle is wanted, that is a separate v18 change.)

## UI

- **A:** the existing "Send to grandMA2…" flow (`AppCommands` File menu +
  `ItemListPane` context menu → `.sendToMA2Requested` → `MA2PushSheetPresenter` →
  `MA2PushSheet`). The sheet's step list loses the two "Upload …" rows and shows the
  command steps; everything else (host/user/password preflight, cancel, progress)
  is unchanged.
- **C:** a sibling "Export grandMA2 plugin…" action in the same two places, opening
  a save panel; no console connection required.

## Testing strategy

- **Reuse/adapt:** `MA2PushPlannerTests`, `MA2PushRunnerTests`, `MA2PushRequestBuilderTests`,
  `MA2PushTargetTests`, `MA2PushPreflightTests`, `MA2TelnetClientTests`,
  `CueCommandsMA2Tests` stay; planner/runner tests are updated for the command-only plan.
- **New:** `MA2CommandPlannerTests` (golden command list incl. fractional numbers,
  fades, ordering, quoting, idempotent delete first); `MA2TrigTimeTests` (per
  framerate 24/25/30/30df, with start-offset, on the frame grid);
  `MA2PluginGeneratorTests` (golden `.lua` + `.xml`, local write+import+remove
  sequence). No test may hit a real console (CI has none).
- `MA2SequenceXMLGeneratorTests` / `MA2TimecodeXMLGeneratorTests` stay green — C
  keeps those generators.

## Build sequence

- **Phase A (live telnet push)** — the unblocker; ship first. Detailed bite-sized
  plan in `docs/superpowers/plans/2026-07-20-ma2-telnet-command-push.md`.
- **Phase C (plugin export)** — its own plan after A lands (reuses A's command
  builder + the existing XML generators).

## Out of scope / follow-ups

- 29.97DF frame-accurate landing under real LTC (verify on a real console + real
  OnlyCue LTC feed).
- Retiring `MA2FTPUploader` entirely (kept until C's local-write plugin covers the
  TC-object case; then the FTP path has no caller).
- A "pinned timecode slot" option (needs schema v18) — only if a user asks.

## Conventions

Conversation zh-TW; code/commits/PRs/issues English. Conventional Commits, no
Co-Authored-By. No direct `ProjectModel` mutations (go through `CueCommands`).
`swiftlint lint --strict` must stay clean. macOS ≥ 14, no App Sandbox, no embedded
media (ADR-001/006/007 unaffected — this feature touches neither).
