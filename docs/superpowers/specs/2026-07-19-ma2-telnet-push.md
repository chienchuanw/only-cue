# Feature: push cues to grandMA2 over Telnet (sequence + timecode)

Status: draft
Issue: TBD
References: roadmap Phase 3 (ConsoleBridge vision), ADR-014 (grandMA export is
best-effort), GMA Toolbox Timecode Creator (prior art), grandMA2 Telnet Remote
(help.malighting.com — port 30000, `login <user> <password>`, full command line).

## Goal

From OnlyCue, connect to a grandMA2 console (or onPC) over Telnet and build a
ready-to-run show skeleton for the selected media clip: create a sequence in a
user-chosen sequence slot, store one (content-empty) cue per OnlyCue cue with
number / label / info / fade, create a timecode object in a user-chosen
timecode slot with one event per cue, and assign the sequence to a user-chosen
executor. Because OnlyCue itself outputs LTC, the pushed timecode show runs in
sync with OnlyCue playback with no manual programming beyond lighting content.

## Decisions (grilled 2026-07-19)

- **Scope**: sequence + cues + timecode show + executor assign (full loop, like
  GMA Toolbox). grandMA2 only; MA3 is out of scope (different command system).
- **Push unit**: one media clip per push (its cues → one sequence slot + one
  timecode slot). Multi-clip batch is out of scope.
- **Target parameters** (push sheet fields): sequence slot, timecode slot,
  executor (`page.exec`), timecode command (Go / **Goto**, default Goto — safer
  when jumping around in rehearsal).
- **Persistence**:
  - Connection (host, port default 30000, username) → app-level Settings, new
    "grandMA2" pane (`@AppStorage`, same pattern as OSC). **Password → macOS
    Keychain**, never UserDefaults.
  - Target parameters + cue-type filter → **per clip, in the document**:
    `MediaItem.ma2PushTarget` (optional struct). `ProjectModel` schemaVersion
    15 → 16 with migration (absent field → nil).
- **Overwrite**: always confirm in-app before sending ("will overwrite Seq X,
  TC Y on the console, and assign to Exec P.E"), then `Delete Seq X /nc` +
  `Delete Timecode Y /nc` and rebuild. No console-state querying (parsing
  telnet feedback for pool occupancy is firmware-fragile; deleting an empty
  slot is a harmless no-op).
- **Entry points**: File ▸ "Send to grandMA2…" (acts on the selected clip, same
  pattern as Export Cues) + media right-click menu item. Both open the push
  sheet: target fields (pre-filled from the clip's saved target), cue count
  summary, per-type filter checkboxes, connection status hint linking to
  Settings, Send button → confirm → stepwise progress.
- **Cue-type filter**: same per-type selection as the Export sheet, reusing
  `CueExportFilter`. Filter selection saved per clip alongside the target.
- **Mechanism (amended 2026-07-19 after research)**: MA confirmed on the
  official forum that timecode events **cannot** be created from the command
  line — only via the GUI or by importing a timecode-show XML. The proven
  remote pipeline (Moving Light Assistant, almost certainly GMA Toolbox's
  "send to console") is: generate MA2 XML files, upload them into the
  console's `gma2/importexport/` over the console's built-in **FTP server**
  (fixed credentials `data`/`data`), then `Import` them from the telnet
  command line. Decision: the **sequence goes the same way** (one sequence
  XML carrying cue numbers / names / info / fades) rather than per-cue telnet
  commands — a 60-cue song imports in one command instead of ~200 throttled
  telnet lines. The telnet session then only runs: login → delete seq/tc →
  import sequence at slot → import timecode at slot → assign seq at exec →
  labels. FTP upload is done via the system `curl` (`/usr/bin/curl -T`,
  FTP is long-deprecated in Foundation); no third-party dependency.
  Exact `Import` syntax/path is validated against a real onPC during
  development (the gma2-mcp server's `send_raw_command` is available for
  interactive verification).
- **Cue mapping**:
  | OnlyCue | grandMA2 |
  | --- | --- |
  | `cueNumber` | cue number (decimals fine) — **used as-is** |
  | `name` | cue label |
  | `notes` | cue info |
  | `fadeTime.fadeIn` / `.fadeOut` | cue fade / outfade |
  | `time` | timecode event time = clip start timecode + `time`, at the project SMPTE framerate |
  | (content) | none — `Store Seq X Cue N /cueonly` stores an empty cue |

  **Pre-flight**: after filtering, every cue must have a unique, non-nil
  `cueNumber`; otherwise the push is blocked with a clear error naming the
  offending cues ("3 cues unnumbered — number them or exclude their type").
  No renumbering, no auto-fill: OnlyCue and MA2 cue numbers must match so
  called cues agree across both.
- **Failure handling**: stop on first error, show which step failed and the
  console's text response. No rollback — every push starts from delete +
  rebuild, so the operation is idempotent and re-pushing after fixing the
  problem is the recovery path.

## Architecture

New `OnlyCue/MA2/` module (mirrors `OnlyCue/OSC/`):

- **`MA2TelnetClient`** — outbound TCP via `Network.framework` `NWConnection`
  to port 30000. `login`, `send(command:) -> String` (send line, read response
  with timeout), disconnect. No third-party dependency. First outbound
  connection in the app; no sandbox (ADR-007) so no entitlement change.
- **`MA2SequenceXMLGenerator`** / **`MA2TimecodeXMLGenerator`** (pure, fully
  unit-testable — the TDD bulk) — given cues + target + clip timecode
  settings, emit the MA2 import XML: sequence XML with one cue per OnlyCue
  cue (number, label, info, fade/outfade), and timecode XML with one Go/Goto
  event per cue on the chosen executor at start-timecode + cue time. Schemas
  cross-checked against real console exports.
- **`MA2PushPlanner`** (pure) — produce the ordered plan: the two XML
  payloads + the telnet command list (login → `Delete Seq X /nc` /
  `Delete Timecode Y /nc` → `Import` sequence at slot → `Import` timecode at
  slot → `Assign Seq X At Exec P.E` → labels). Exact syntax cross-checked
  against the gma2-mcp implementation and the MA2 manual during TDD.
- **`MA2FTPUploader`** — uploads the generated XML into the console's
  `gma2/importexport/` via system `curl` (`Process`), fixed `data`/`data`
  credentials, same host as telnet.
- **`MA2PushRunner`** — generate XML → FTP upload → feed the telnet plan
  through the client step by step, reporting progress and stopping on error.
- **`MA2ConnectionSettings`** (`@AppStorage` keys) + **`MA2Keychain`** (small
  Keychain wrapper for the password) + **`MA2SettingsView`** (Settings pane).
- **`MA2PushSheet`** (+ presenter) — the push UI described above.
- **`MediaItem.ma2PushTarget: MA2PushTarget?`** — `{ sequenceSlot, timecodeSlot,
  executorPage, executorNumber, timecodeCommand, includedTypeIDs }`, Codable,
  schema v16 migration.

## What stays the same

- Existing CSV/MA2/MA3 file export untouched.
- No App Sandbox (ADR-007), no embedded media (ADR-006), macOS 14.0 floor.
- OSC server, LTC output, show mode: unchanged.

## Test plan (TDD)

- **Unit — XML generators** (bulk of the coverage): sequence XML for a known
  cue set (numbers incl. decimals, labels with XML escaping, info, fades);
  timecode XML (event times with start-timecode offset at each framerate,
  Go vs Goto, executor reference); golden-file comparison against
  console-validated samples.
- **Unit — planner**: telnet command list (delete-first, import at the right
  slots, executor assign, labels); pre-flight rejection (unnumbered /
  duplicate numbers) with the offending cues named; filter application.
- **Unit — model**: `MA2PushTarget` Codable round-trip; schema v15 → v16
  migration (old documents load, field nil).
- **Unit — client**: against a local loopback TCP fixture (spawn a listener in
  the test): login handshake, command/response framing, timeout.
- **UI**: push sheet renders fields + summary; pre-flight error path;
  screenshot test consistent with existing sheet tests. No test connects to a
  real console.
