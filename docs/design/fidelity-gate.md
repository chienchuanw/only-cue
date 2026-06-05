# Figma ↔ App fidelity gate

How OnlyCue keeps the app matching the Figma design system, and how to stop drift from recurring. Written after the 2026-06-05 audit (`figma-audit-2026-06-05.md`) found 88 deltas that had accumulated because comparison was ad-hoc (eyeballing screenshots) with no enforcement.

## Why drift kept happening

1. **Eyeballing, not measuring.** Differences were spotted by looking at screenshots and fixing the obvious surface ones (colors, text). Layout/proportion gaps (e.g. the waveform pinned to 100pt vs Figma's ~602pt) are invisible to a casual look and obvious the moment you read Figma's coordinates.
2. **No enforcement.** Screenshot tests captured baselines that a human compared; nothing *failed* when the app drifted, so gaps surfaced only when someone looked again.
3. **Region-scoped passes.** Each fix touched the noticed area and stopped; un-audited regions were never checked.

## The gate (three layers)

### 1. Coordinate-level audits (find drift)

Compare against Figma's actual measurements, not a screenshot. For each region, pull `get_metadata` (exact x/y/w/h of every node) via the Figma MCP and diff against the app code. The 2026-06-05 sweep did this with one agent per region; re-run the same way when the design changes. Output: a per-delta list (element, Figma spec, app value, severity, fix) like `figma-audit-2026-06-05.md`.

Frame/node references live in the audit doc and in `memory/figma-design-system.md`.

### 2. Structural assertions (catch regressions in CI, deterministically)

`OnlyCueTests/FigmaFidelityTests.swift` is the single greppable contract: each load-bearing, Figma-derived value is asserted with its node id (dark-only chrome, achromatic waveform, the cue-list TIME floor, the preview video/waveform split, compact durations, …). These are renderer-independent, so they pass/fail identically on every machine. Per-feature suites (`DSColorTests`, `WaveformViewColorTests`, `CueListColumnWidthsTests`, `PreviewLayoutTests`, `CompactDurationTests`) hold the exhaustive cases.

**When you add or change a main-window surface:** pull its Figma `get_metadata`, implement to those numbers, and add/adjust the matching assertion here. New chrome must also consume `DS.*` tokens (enforced by `TokenConformanceTests`, ADR-024).

### 3. Visual baselines (human review for pixel-level fidelity)

`docs/design/audit-screenshots/` holds the Figma reference frames (`figma-*-dark.png`) paired with the app captures (`app-*-dark.png`). The `*ScreenshotTests` regenerate the app captures deterministically (seeded, dark, playhead at 0 → no dynamic content). A reviewer diffs the pair at PR time for anything the structural assertions can't express (spacing rhythm, weight, exact fills).

## PR review checklist (UI changes)

- [ ] Pulled the relevant Figma node `get_metadata`; implemented to the measurements.
- [ ] New/changed load-bearing values asserted in `FigmaFidelityTests` (with node id).
- [ ] New chrome consumes `DS.*` tokens (TokenConformance passes).
- [ ] Regenerated the affected `app-*-dark.png` baseline and eyeballed it against `figma-*-dark.png`.

## Future increment: automated pixel-diff in CI

A test that loads a committed golden PNG (as a test-bundle resource), captures the app in the matching seeded state, and fails on mean-pixel-difference above a tolerance — with dynamic regions (timecodes) masked. Deferred, not done, because: the UI-test runner is sandboxed (golden must be a bundled resource, not a repo path read), and a live AppKit render vs a committed golden carries cross-machine render noise (font hinting, retina scale) that needs a tuned tolerance to avoid false reds. Tracked in the consolidated follow-up. Until then, layer 3 is the human-reviewed pixel check and layer 2 is the automated gate.
