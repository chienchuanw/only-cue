# grandMA2 push — UX refinements (console discovery, editable sequence name, cue info) — design

**Spec section implemented:** extends the grandMA2 push (#683, shipped v0.15.0 — see
`docs/superpowers/specs/2026-07-20-ma2-telnet-command-push-and-plugin-export-design.md`).
**Status:** design, pending approval. Rig facts gathered on grandMA2 onPC `2.0.0.193`.

## Problem

Three usability gaps in the shipped push:

1. **Console host is free text.** The user must know and type the console IP. The Mac
   is usually attached to the console's MA-net (here `en7` = `2.0.0.111`, a /8), so a
   dropdown of discovered consoles would remove the guesswork.
2. **The sequence name is invisible and non-editable.** It is silently derived from
   the clip's resolved name (`item.resolvedName`), which is often non-English —
   grandMA2 names are effectively ASCII-only. The user should see the name that will
   be sent and be able to edit it.
3. **Cue info is dropped on the live path.** OnlyCue cues carry `notes`; the XML/plugin
   path already writes them into grandMA2's cue Info (`<InfoItems><Info>`), but the
   Approach-A telnet command path (`MA2CommandPlanner`) omits them entirely.

## Rig facts that shape the design

- The Mac sits directly on the MA-net via `en7` (`2.0.0.111`, netmask /8) and also on a
  normal LAN via `en0` (`192.168.0.87`, /24); Tailscale `utun2` is a /32 point-to-point.
- A bounded TCP scan of `2.0.0.0/24:30000` finds the console in **~0.8 s** (128-way
  parallel). Scanning the whole /8 is infeasible; scanning the interface's /24 is not.
- `Assign Sequence <seq> Cue <n> /info="hello world"` is **accepted** by the console
  (no error); `/note=` returns `Error #66`, so `/info` is the correct keyword.

## Item 1 — Console discovery

### Approach (chosen: bounded TCP-30000 scan + banner verification)

Rejected alternative — **MA-Net broadcast listen**: grandMA2's station-announcement
protocol is undocumented and firmware-fragile; not worth the reliability risk.

`MA2ConsoleScanner` (pure/async, no UI):

1. **Enumerate scan subnets** via `getifaddrs`: for each **up, non-loopback,
   non-point-to-point** IPv4 interface (here `en0` and `en7`; `utun*`/point-to-point
   skipped), take the `/24` around the interface address (`addr & 0xffffff00`). This
   deliberately scans the interface's /24 even when the mask is wider (the MA-net /8),
   because consoles cluster near the station's own address.
2. **Probe** every host `.1–.254` in each subnet for TCP `30000` (parallel, ~0.4 s
   timeout each). De-dupe across interfaces.
3. **Verify** each responder is really a console: open the telnet port, read the banner
   for ~0.5 s, and keep only hosts whose banner carries a grandMA2 marker (`Please
   login`, `[Channel]`, or the MA login art) — this filters out unrelated services that
   happen to have 30000 open on the office LAN.
4. Return `[MA2Console]` (`host`, optional `label`), the Mac's own interface IPs excluded.

### UI

Settings → grandMA2 pane: the host `TextField` becomes an editable **combo** — a
`Picker`/menu of discovered consoles beside a **"Scan" button** with a spinner, and
manual typing still allowed. The selection writes to the same `@AppStorage`
`MA2ConnectionSettings.hostKey`. Scanning is always **user-initiated** (a button), never
automatic, so opening Settings never fires network traffic. An empty scan shows "No
consoles found on 192.168.0.0/24, 2.0.0.0/24".

## Item 2 — Editable, sanitized sequence name

- **Sanitizer** (`MA2Name.sanitize(_:)`, pure): keep printable ASCII, drop non-ASCII
  (CJK, accents) and the already-stripped `"`; collapse runs of whitespace; trim. If the
  result is empty, fall back to `"OnlyCue <sequenceSlot>"`.
- **Sheet field:** the push sheet gains an editable **"Sequence name"** text field,
  pre-filled from the saved target's `sequenceName` if set, else `sanitize(item.resolvedName)`.
  This name drives the sequence `Label` **and** the timecode name (`"<name> TC"`).
- **Persistence:** add optional `sequenceName: String?` to `MA2PushTarget` (**schema
  v17 → v18** + migration; `nil` on decode of old docs). Saved via the existing
  `CueCommands.setMA2PushTarget` when a push proceeds, so the English name sticks across
  re-pushes instead of re-sanitizing every time. The command/plugin planners take the
  resolved name from the target (falling back to the sanitized clip name when `nil`).

## Item 3 — Cue info → grandMA2 Info

- **Command path (`MA2CommandPlanner`):** for each cue with non-empty `notes`, emit
  `Assign Sequence <seq> Cue <num> /info="<info>"`, where `<info>` is the notes with
  embedded `"` stripped (reusing `MA2CommandQuoting.quotable`) and newlines collapsed to
  spaces (the telnet line is CRLF-framed — a literal newline would split the command).
  Emitted right after the cue's `/Trig`/`/TrigTime`/fades.
- **Plugin/XML path:** unchanged — `MA2SequenceXMLGenerator` already writes `notes` into
  `<InfoItems><Info>`.
- **Caveat:** telnet has no read-back, so the info value's on-console display is confirmed
  by eye during rig validation (tracked with the existing #685 real-console pass).

## Data model / schema

`MA2PushTarget` gains `sequenceName: String?` → `ProjectModel.currentSchemaVersion`
**17 → 18** with a migration (`ProjectModel+MigrationV18`) that leaves existing targets'
`sequenceName` as `nil` (the sanitized clip name remains the default). No other model
change. ADR-006/007 unaffected.

## Components

| Unit | Responsibility |
| --- | --- |
| `MA2ConsoleScanner` (new) | Enumerate interface /24s, scan :30000, banner-verify → `[MA2Console]` |
| `MA2Name` (new) | `sanitize(_:) -> String` (ASCII-only, whitespace-collapsed, fallback) |
| `MA2SettingsView` (mod) | Host combo + Scan button + spinner + empty-state |
| `MA2PushSheet` (mod) | Editable "Sequence name" field; passes it into the planners |
| `MA2PushTarget` (mod) | `+ sequenceName: String?`; v18 |
| `MA2CommandPlanner` (mod) | Take the resolved name; emit `/info=` per cue notes |
| `MA2PushRequestBuilder` (mod) | Thread the target's sequence name / sanitized default |

## Testing

- `MA2ConsoleScannerTests` — an in-process `NWListener` on 30000 that serves a fake MA
  banner is discovered; a listener that serves a non-MA banner is rejected; the probe/
  subnet-enumeration seams are injected (no real network).
- `MA2NameTests` — CJK → fallback; accents dropped; quotes stripped; whitespace
  collapsed; already-ASCII passes through.
- `MA2CommandPlannerTests` — `/info="…"` emitted for a cue with notes (newlines
  collapsed, quotes stripped), omitted when notes empty; existing golden order preserved.
- `MA2PushTargetTests` + a v18 migration test — old doc decodes with `sequenceName == nil`.
- `MA2PushRequestBuilderTests` — resolved name comes from the target when set, else the
  sanitized clip name.

## Out of scope

- MA-Net broadcast/native discovery (undocumented).
- Transliterating CJK to romanized text (we drop, not romanize; user edits).
- Any change to the plugin/XML info handling (already correct).

## Conventions

Conversation zh-TW; code/commits/PRs English. Conventional Commits, no `Co-Authored-By`.
No direct `ProjectModel` mutations (via `CueCommands`). Schema bump + migration is
mandatory for the new field. `swiftlint --strict` clean. macOS ≥ 14.
