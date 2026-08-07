# 繁體中文 (zh-Hant) localization — design

**Status:** implemented — Phase 1 (#723, PR #725) and Phase 2 (#724, PR #726) both merged.
**Spec section implemented:** this file is the spec; see the OnlyCue verification footer of PR #725 (Phase 1) and PR #726 (Phase 2).

## Problem

OnlyCue is English-only. `project.yml` sets `developmentLanguage: en`, there are no `.lproj`/`.strings`/`.xcstrings` files, and no `NSLocalizedString`/`String(localized:)`/`LocalizedStringKey` call sites. The 108 `Text("literal")` usages are implicitly localizable (SwiftUI treats a bare string literal as a `LocalizedStringKey`), but non-`Text` UI (buttons, alerts, menus, `.help(…)`, accessibility labels), interpolated strings, and any strings built in view models / commands are not routed through a catalog.

We want OnlyCue fully usable in **繁體中文 (zh-Hant)** for Taiwanese lighting designers, without changing the English experience.

## Goals

- A complete zh-Hant UI pass — no half-translated surfaces. Every user-facing in-app string is either translated or intentionally kept in English per the glossary.
- An in-app language picker (System / English / 繁體中文), restart-to-apply.
- The English experience is unchanged for existing users by default (picker defaults to "System").
- A regression guard that goes red when a zh-Hant string is missing or stale.

## Non-goals

- Simplified Chinese (zh-Hans). Deferred — a mechanical second column in the same catalog later; no architecture change.
- Localizing docs, README, release notes, GitHub templates, or marketing.
- Live (no-restart) language switching.
- Localizing technical formats (timecode `HH:MM:SS:FF`, raw numbers, BPM digits).

## Decisions (from grill 2026-08-06)

1. **Language:** zh-Hant only.
2. **Scope:** App UI only, complete pass.
3. **Terminology — hybrid.** Translate general UI (Save, Import, Settings, confirmations). **Keep entrenched lighting jargon in English:** Cue, Cue list, Executor, Sequence, Timecode/LTC, MA2/grandMA2, MIDI, OSC, Fixture, GO, BPM, Blackout, Waveform, Beat grid. The keep-English list lives in a repo-root **`CONTEXT.md`** glossary (created by this work) and is the source of truth for where the translate/keep-English line falls.
4. **Delivery mechanism:** in-app language picker, **restart-to-apply** — writes the `AppleLanguages` user default; the app is relaunched to pick up the new bundle localization. Not live-switching.
5. **Picker location:** a new **"General"** tab in the existing Preferences (`Settings {}`) scene in `OnlyCue/App/OnlyCueApp.swift`. The Preferences window is not the dark-only document window (ADR-029), so verify the tab renders correctly.
6. **Picker options:** **System (default)** / English / 繁體中文.
7. **Restart UX:** changing the picker shows an alert **"Relaunch to apply?"** (Relaunch / Later). Never auto-quit — a `.cuelist` may be open and unsaved.
8. **Format:** String Catalog (`.xcstrings`).
9. **Regression guard:** a test that fails on any untranslated / `needs_review` zh-Hant entry (in the spirit of `TokenConformanceTests`).
10. **Authorship:** drafts follow the glossary; the maintainer (native speaker + domain expert) reviews before merge.

## Implementation risks to watch (not decisions)

- `String(localized:)` resolves against the launch-time main bundle — correct for restart-to-apply, but every such call must be reachable by the catalog harvester.
- Interpolated `LocalizedStringKey` format specifiers (`Text("\(name) → …")`) must produce stable catalog keys.
- AppKit-side strings: menu items, window titles, and anything set outside SwiftUI `Text`.
- macOS per-app language override (System Settings → General → Language & Region) interaction with the in-app `AppleLanguages` write.

## Delivery — two phases

### Phase 1 — localization-ready (English-only, no behavior change) — done (#723, PR #725)

- Add a String Catalog (`Localizable.xcstrings`) and wire it into `project.yml` (add `knownRegions` / resource so xcodegen includes it); keep `developmentLanguage: en`.
- Create repo-root `CONTEXT.md` with the keep-English glossary.
- Refactor all non-`Text` user-facing strings to route through the catalog: `Button`, alerts, confirmation dialogs, menus, `.help(…)`, accessibility labels/hints, interpolated strings, and strings assembled in view models / commands.
- Add the completeness test in **keys-exist mode** (every user-facing key is present in the catalog; no assertion about zh-Hant yet).
- Wide, mechanical, English-only diff. Safe to merge alone; app behaves identically.

### Phase 2 — the Chinese feature — done (#724, PR #726)

- Add the **General** Preferences tab with the System/English/繁體中文 picker, persisted to `AppleLanguages` (default: System), plus the "Relaunch to apply?" alert and relaunch action.
- Add `zh-Hant` to the catalog and fill translations per the glossary (draft → maintainer review).
- Flip the completeness test to **require translation** — red on any missing / `needs_review` zh-Hant entry.

Follow-up (#727): model keep-English glossary terms with `shouldTranslate: false` rather than `state: translated` with an English value, so the completeness gate can distinguish intentional-English from forgotten translations.

## Verification (TDD)

- Phase 1: completeness test (keys-exist) written red first; UI unchanged (existing tests stay green).
- Phase 2: completeness test flipped to require-translation (red until translations land); a UITest launches the app forced to zh-Hant and asserts a representative translated string renders in Chinese and a glossary keep-English term (e.g. "Executor") stays English.
