# Plan: push cues to grandMA2 (#683)

Spec: `docs/superpowers/specs/2026-07-19-ma2-telnet-push.md`. Branch:
`issues/683`. TDD throughout — failing test committed first per step when
practical.

## Step order (each step = red test → green → commit)

1. **`MA2PushTarget` model + schema v17** — Codable struct
   (`sequenceSlot`, `timecodeSlot`, `executorPage`, `executorNumber`,
   `timecodeCommand: .go/.goto`, `includedTypeIDs: Set<UUID>`), field
   `MediaItem.ma2PushTarget: MA2PushTarget?`; bump `currentSchemaVersion` to
   17 + `ProjectModel+MigrationV16.swift` (structural no-op, absent → nil,
   modeled on `MigrationV15`). Tests: round-trip; v16 doc loads with nil.
2. **Pre-flight validation** — `MA2PushPreflight.validate(cues:) ->
   [Issue]` naming unnumbered / duplicate-numbered cues (after
   `CueExportFilter`). Pure; tests first.
3. **`MA2SequenceXMLGenerator`** — pure `(cues, target, clipName) -> String`.
   Golden-file tests: numbers incl. decimals (3.2 → number=3 sub_number=2 —
   careful: OnlyCue cueNumber is Double; sub_number digits from the decimal
   string, verify 1.15 vs 1.5 handling and document), XML escaping in
   name/info, basic_fade/basic_outfade, cue-zero placeholder, wrapper attrs.
4. **`MA2TimecodeXMLGenerator`** — pure. Tests: frame conversion at each
   `SMPTEFramerate` (× fps, rounded), start-timecode offset added, `time`
   omitted at frame 0, Go vs Goto, exec `<No>30/1/page/exec</No>`, cue ref
   `<No>1/seq/index</No>`, `lenght` attr, step numbering.
5. **`MA2PushPlanner`** — pure: filenames + telnet command list
   (login, delete ×2 `/nc`, import seq (cd navigation), import tc, assign
   exec, labels). Tests: exact command strings and order.
6. **`MA2TelnetClient`** — NWConnection, CRLF framing, login send, response
   read with timeout, `Error #` detection. Tests against an in-process TCP
   listener fixture (loopback), as `OSCServer` tests do for UDP.
7. **`MA2FTPUploader`** — `Process` + `/usr/bin/curl -T <tmpfile>
   ftp://host/gma2/importexport/<name> --user data:data`. Thin; test command
   assembly (pure `curlArguments(...)` function), not a live FTP.
8. **`MA2ConnectionSettings` + `MA2Keychain`** — AppStorage keys enum;
   Keychain add/read/delete wrapper (`kSecClassGenericPassword`,
   service "OnlyCue-MA2"). Unit test Keychain round-trip.
9. **`MA2SettingsView`** — Settings pane (host, port, user, password field
   writing to Keychain). Screenshot test per existing settings-pane tests.
10. **`MA2PushRunner`** — orchestrates generate → upload → telnet steps,
    `@Observable` progress: array of steps with pending/running/ok/fail +
    console response on failure. Unit test with protocol-mocked
    client/uploader.
11. **`MA2PushSheet` + presenter + entry points** — File ▸ Send to grandMA2…
    (notification pattern like Export Cues) + media right-click item; sheet
    with target fields (pre-filled from `ma2PushTarget`), type filter,
    pre-flight errors, overwrite confirmation, progress list; saving target
    back to the document goes through a new `CueCommands` mutation (no
    direct ProjectModel mutation). UI screenshot test + hosted tests.
12. **Docs** — `CONTEXT.md` note, `docs/osc-companion-ma3.md` untouched,
    README feature bullet (after merge), ADR for the FTP+XML mechanism.
13. **Real-rig validation (gated)** — with the user's onPC/console online:
    verify FTP availability, exact Import syntax, end-to-end push, then
    update golden files if the firmware differs. Blocks merge.

## Risks

- Cue `sub_number` semantics for multi-digit decimals (1.15) — resolve
  against real export in step 13; until then document the chosen rule.
- onPC may lack the FTP server (spec open question) — fallback decided with
  the user if so.
- `xcodegen generate` needed after adding `OnlyCue/MA2/` (folder rules
  should pick it up; verify).
