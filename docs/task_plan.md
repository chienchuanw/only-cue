# Task Plan

Working source of truth for what's left. Sourced from the [GitHub issue board](https://github.com/chienchuanw/only-cue/issues) and the build sequence. When in doubt, the issues are authoritative.

## Active milestone — MVP

| Issue | Title | Status |
|---|---|---|
| [#1](https://github.com/chienchuanw/only-cue/issues/1) | C1 bootstrap | ✅ shipped (PR #14) |
| [#2](https://github.com/chienchuanw/only-cue/issues/2) | C2 CI — GitHub Actions, build + XCTest + XCUITest | ✅ shipped (PR #15) |
| [#3](https://github.com/chienchuanw/only-cue/issues/3) | E1 skeleton — `DocumentGroup`, `ProjectModel`, `.cuelist` UTType | ⏭️ next |
| [#4](https://github.com/chienchuanw/only-cue/issues/4) | E2 player core | pending |
| [#5](https://github.com/chienchuanw/only-cue/issues/5) | E3 media import | pending |
| [#6](https://github.com/chienchuanw/only-cue/issues/6) | E4 video preview | pending |
| [#7](https://github.com/chienchuanw/only-cue/issues/7) | E5 waveform | pending |
| [#8](https://github.com/chienchuanw/only-cue/issues/8) | E6 cue list pane | pending |
| [#9](https://github.com/chienchuanw/only-cue/issues/9) | E7 add/edit/delete cues | pending |
| [#10](https://github.com/chienchuanw/only-cue/issues/10) | E8 cue markers | pending |
| [#11](https://github.com/chienchuanw/only-cue/issues/11) | E9 polish | pending |
| [#12](https://github.com/chienchuanw/only-cue/issues/12) | E10 distribution (blocked by #13) | pending |
| [#13](https://github.com/chienchuanw/only-cue/issues/13) | C3 release pipeline | pending |

## Recommended order

1. ~~**#2 (C2 CI)** — green-build gate.~~ Done.
2. **#3 (E1 skeleton)** — first real feature work. Define `ProjectModel`, `Cue`, `MediaReference` Codable types; register the `.cuelist` UTType in `Info.plist`; wire `OnlyCueApp` to `DocumentGroup` with a `CueListDocument`. This is the first PR with TDD applied (Codable round-trip test red → green).
3. **#4..#11 (E2..E9)** — feature epics in build-sequence order. Leaves expanded JIT once #3 lands.
4. **#13 (C3) → #12 (E10)** — release pipeline first, then the actual ship.

## Phase 2 / Phase 3 milestones

Empty placeholders. Phase 2 (LTC, templates, export, custom shortcuts) and Phase 3 (the differentiator — TBD) get their own epics added when the MVP is feature-complete. See `docs/roadmap.md`.
