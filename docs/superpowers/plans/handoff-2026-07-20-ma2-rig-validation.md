# Handoff — 2026-07-20 (MA2 push: real-rig validation, #683 / PR #684)

**Repo:** `chienchuanw/only-cue` · **Branch:** `issues/683` (off `dev`) · **PR:** #684 (draft, CI green)
**Task:** plan step 13 — validate the "Send to grandMA2" push against a real grandMA2 onPC/console.
This is the **only remaining blocker**; all code, tests (1171 green), lint, and adversarial-review
fixes are done and pushed. Do **not** merge or flip the PR to ready until every item below passes
and the user confirms.

## What the feature does

Push one media clip's cues to a grandMA2 (v3.9) as a sequence + timecode show:

1. Generate two XML files (`MA2SequenceXMLGenerator`, `MA2TimecodeXMLGenerator` in `OnlyCue/MA2/`).
2. Upload both via the console's built-in FTP (`data`/`data`) into `gma2/importexport/`
   using system curl (`MA2FTPUploader`).
3. Telnet (TCP 30000, `MA2TelnetClient`) runs, in order (`MA2PushPlanner.swift:69-80`):

   ```
   Delete Sequence <seq> /nc
   Delete Timecode <tc> /nc
   cd Sequences
   cd Global
   Import "<seqfile>" At <seq> /nc
   cd /
   Import "<tcfile>" At Timecode <tc> /nc
   Assign Sequence <seq> At Exec <page>.<exec>
   Label Sequence <seq> "<name>"
   Label Timecode <tc> "<name>"
   ```

Entry points: **File ▸ Send to grandMA2…** or right-click a media item. Console host/port/username
live in Settings (`@AppStorage`), password in the macOS **Keychain** (never UserDefaults).
Push is stop-on-first-error and idempotent — re-push is the recovery path.

## Setup on this machine

```bash
git clone git@github.com:chienchuanw/only-cue.git && cd only-cue
git checkout issues/683
brew install xcodegen   # if missing
xcodegen generate
open OnlyCue.xcodeproj  # or: xcodebuild build -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS' CODE_SIGN_IDENTITY="-"
```

Unit suite (should be 1171 green):

```bash
xcodebuild test -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" -only-testing:OnlyCueTests
```

Console address: from the home machine the onPC was `100.110.79.101` (Tailscale); on the studio
machine use the local address (or `127.0.0.1` if onPC runs on the same box). Verify reachability
first: `nc -z <host> 30000` and `nc -z <host> 21`.

## Safety

- Use a **scratch showfile** on the console/onPC — the push **deletes** the target Sequence and
  Timecode slots unconditionally before rebuilding. Pick empty slots (e.g. Seq 900, TC 9).
- Save the show before testing (`SaveShow` / backup) so anything can be rolled back.

## Validation checklist (all must pass; record actual console output for each)

Pre-tests can go through the `gma2-mcp` server's `send_raw_command` if configured, or a plain
`nc <host> 30000` session (`login "administrator" ""` … commands are CRLF lines; errors print
`Error #NN`; many `/nc` commands print nothing = success).

1. **FTP availability on onPC** — spec open question: onPC may not run the FTP server at all.
   `curl --user data:data ftp://<host>/gma2/` should list; then upload a scratch file into
   `gma2/importexport/`. If FTP is absent, STOP and discuss fallback with the user
   (e.g. writing directly into the onPC `gma2/importexport` folder on disk).
2. **Import syntax** — from telnet, run the exact command sequence above against the uploaded
   files. Watch specifically:
   - the `cd Sequences` → `cd Global` → `Import … At <slot>` dance (argument order is flipped
     vs Export; wrong order → `Error #12`),
   - `Import … At Timecode <tc>` from root,
   - whether filenames need/reject the `.xml` extension.
3. **sub_number thousandths** — push cues with fractional numbers (e.g. 1.15, 1.5, 2.001) and
   verify the console shows the intended cue numbers (`MA2CueNumber` encodes thousandths).
4. **fps30drop** — with project framerate 29.97DF, events are emitted as *physical* frame counts
   under a non-drop `frame_format="30 FPS"` label (see comment in
   `MA2TimecodeXMLGenerator.swift`). Check where events land when the TC show is chased/played —
   if drifted, this becomes a follow-up fix before DF pushes are supported.
5. **End-to-end push from the app** — configure Settings (host/user/password), open a project
   with cues, File ▸ Send to grandMA2…, confirm overwrite, watch the step list complete.
   Verify on the console: sequence contents + names/fades, timecode events at correct times,
   executor assignment, labels.
6. **Idempotent re-push** — push the same clip again to the same slots; must succeed and leave
   exactly one copy of everything.
7. **Error paths (spot check)** — wrong password → login rejected (message must NOT contain the
   password); console unreachable → connect timeout ~5 s; kill mid-push → Cancel button works.

## Reporting back

- Comment the results (pass/fail per item + raw console responses for failures) on **PR #684**.
- If firmware output differs from our golden XML fixtures, update the fixtures/tests on
  `issues/683` and push (CI must stay green).
- If everything passes: tell the user; flipping #684 draft→ready and merging happens only with
  the user's go-ahead. After merge: README feature bullet, then offer a release.

## Conventions (non-negotiable)

- Conversation zh-TW; code/commits/PRs/issues in English.
- Conventional Commits, lowercase imperative, **no Co-Authored-By / attribution**.
- No direct `ProjectModel` mutations (go through `Commands/CueCommands.swift`).
- CI is `swiftlint lint --strict` — warnings fail.
