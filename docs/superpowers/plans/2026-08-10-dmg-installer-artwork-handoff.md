# Handoff — branded DMG installer artwork (#741)

**Date:** 2026-08-10
**Resume on branch:** `issues/741` (created off `dev`, pushed; spec + plan + this handoff committed)
**Issue:** #741
**Spec:** `docs/superpowers/specs/2026-08-10-dmg-installer-artwork-design.md` (approved)
**Plan:** `docs/superpowers/plans/2026-08-10-dmg-installer-artwork.md` (approved — contains the FULL generator code + exact `make-dmg.sh` edits + verification)

## What this is

Give the OnlyCue `.dmg` installer window a dark, on-brand background instead of the default blank `create-dmg` layout. Design was locked from rendered mockups: dark brand gradient, cool-white glow behind the app icon, a "like a real song" vertical-bar waveform (achromatic grey) with two indigo cue markers (the icon's playhead motif), and a precise straight arrow with an origin node pointing to Applications. Finder draws the live app icon / Applications folder / labels / title bar ON TOP — the background art must NOT include those.

## State so far (nothing implemented yet)

Committed on `issues/741`:
- The spec (design decisions, palette, layout anchors, deterministic waveform formula).
- The plan (2 tasks, both with verbatim code/edits).
- This handoff.

NOT yet done (this is the remaining work — just execute the plan):
- `scripts/generate-dmg-background.swift` — not created.
- `scripts/dmg-assets/dmg-background.png` + `@2x` — not generated/committed.
- `scripts/make-dmg.sh` — not yet wired to `--background`.

## Remaining work — execute the plan's two tasks

1. **Task 1 — generator + committed PNGs.** Create `scripts/generate-dmg-background.swift` (full code is in the plan), run it, verify dimensions (`sips`: 600×400 and 1200×800) and determinism (md5 identical across two runs), eyeball the art (no live icons — expected), commit script + both PNGs.
2. **Task 2 — wire into `make-dmg.sh`.** Add the Retina TIFF step (`tiffutil -cathidpicheck` the two PNGs) and update the `create-dmg` call (`--background`, `--window-size 600 400`, `--icon-size 112`, `--icon "OnlyCue.app" 168 165`, `--app-drop-link 432 165`). Then `RELEASE_MODE=unsigned bash scripts/build-release.sh && … make-dmg.sh`, **mount the DMG, `screencapture` the window, and confirm** the icon sits in the glow / folder on the right / arrow between. **Calibrate** the two icon coordinate pairs if Finder places them off the art anchors (empirical — see Task 2 Step 4). Commit `make-dmg.sh`.

Then: PR (feat template `.github/PULL_REQUEST_TEMPLATE/feat.md`, OnlyCue verification footer, Closes #741) → CI green → rebase-merge into `dev`, `--delete-branch`.

## Gotchas / locked decisions

- **Art excludes live icons/labels/title bar** — those are Finder-drawn. The generator renders only the 5 background layers.
- **Deterministic art** — the waveform is a pure function of constants + a fixed integer hash (no unseeded randomness), so the committed PNGs are byte-stable. Keep it that way (the plan's determinism check guards it).
- **Retina** — assemble a hidpi background with `tiffutil -cathidpicheck dmg-background.png dmg-background@2x.png -out …tiff` at build time and pass the `.tiff` to `create-dmg --background`. This is the proven retina-DMG method; verify crispness on a Retina display in the mount screenshot.
- **Finder icon coordinates are calibrated empirically**, not assumed — mount and nudge `--icon`/`--app-drop-link` until aligned (initial guess: `168 165` / `432 165` for the 600×400 window).
- **Prereqs to build the DMG:** `create-dmg`, `tiffutil`/`sips` (built-in), and `scripts/build-release.sh` must have produced `build/export/OnlyCue.app` first. Use `RELEASE_MODE=unsigned`.
- **No app/runtime/schema code is touched** — this is build tooling only; no unit-test suite or `ProjectModel` impact. Verification is dimensional + a mounted-DMG screenshot (per the repo's "real screenshots" rule).
- **Scratch mockup** `/tmp/dmg_mockup.swift` from the design session is NOT committed and won't exist in a new session — you don't need it; the plan's Task 1 embeds the final art-only generator code (the mockup additionally drew the live icons/labels/title bar for preview, which the real generator omits).
- **Release context:** `dev` is currently 1 commit ahead of the v0.23.0 `main` (from #739). This DMG work would ride the next fast-forward/release (e.g. a v0.23.1 patch), not a separate release by itself.

## Suggested resume prompt

Paste the block in `HANDOFF-PROMPT.md`-style (see the session message) into the new session.
