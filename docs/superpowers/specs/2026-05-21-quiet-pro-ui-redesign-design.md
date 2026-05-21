# Quiet Pro — Main Window UI Redesign — Design

**Date:** 2026-05-21
**Status:** Approved
**Proposed ADR:** ADR-024 — adopt the "Quiet Pro" design-token system (see §11)
**Touches:** `OnlyCue/UI/` (new `DesignSystem/` group + main-window view retrofit), `docs/decisions.md` (ADR-024 added, ADR-023 amended), README screenshots
**Schema:** no `ProjectModel` change — this redesign is presentational only

## 1. Goal

OnlyCue's main document window works but does not yet *read* as a professional tool. The empty state stacks an app-name wordmark, a disabled transport, a "0 cues" line, a placeholder box, and a monospace cheat-sheet all at once; the inspector's empty-state copy is clipped; spacing is ad-hoc; colors and fonts are applied per-view with no shared vocabulary.

This design makes the main window **professional and minimalist** by introducing a centralized design-token system ("Quiet Pro") and applying it across the main-window view set, together with a small set of targeted structural fixes. It is a retheme plus targeted layout work — not a re-architecture. The three-pane `NavigationSplitView` is unchanged.

## 2. Scope and non-goals

**In scope** — the main document window only:

- The three-pane `NavigationSplitView`: media sidebar (`ItemListPane`), preview + transport center (`PreviewPane`, `TransportBar`), cue inspector (`ModeAwareInspector` / `CueListPane`).
- Empty states, the LTC strip, the editor-mode switcher.
- A new `OnlyCue/UI/DesignSystem/` token layer.

**Out of scope** (future follow-up passes):

- The ~12 sheets (Export, OSC Monitor/Settings, Audio/Keyboard/Timecode settings, Manage Types, Cue Notes/Tempo, Media Edit, First Launch, Notes Overlay prefs). The token layer is designed so retrofitting them later is mechanical.
- The two projected overlays (Notes, Lyrics) — those address a second-screen audience, a different design problem.
- Any behavior change beyond closing the named usability gaps. No new features.
- Any `ProjectModel` / `.cuelist` schema change.

## 3. Decisions locked during brainstorming

| # | Decision |
|---|----------|
| 1 | Aesthetic: **Quiet Pro** — Apple pro-app restraint; achromatic chrome; cue-type color is the only chroma; SF Mono for all numerals; mode-agnostic; keeps the native SwiftUI base. |
| 2 | Scope: **main document window only**; the design system is the real deliverable. |
| 3 | Depth: **retheme + targeted layout fixes**; the 3-pane architecture is protected. |
| 4 | Dark mode: **dark-ready, light-verified** — tokens are appearance-aware so dark works by construction; light is the test-verified mode. |
| 5 | Behavior: **presentational + close usability gaps**; no new features. |
| 6/7 | Transport: **B+** — a complete zoned transport (controls · timecode · next-cue), no second scrubber. The waveform timeline stays the single seek surface. |
| 8 | Done: **token conformance + a structural-fix punch-list + screenshot sign-off**. |

## 4. Design-system architecture

A new group, `OnlyCue/UI/DesignSystem/`, holds the token layer. It follows the idiom already established by `CueListInspectorMetrics` (an `enum` namespace of `static` constants plus `View` extensions), so it is not a foreign pattern in this codebase.

```
OnlyCue/UI/DesignSystem/
  DS.swift               — enum DS namespace; DS.Space, DS.Radius, DS.Motion
  DSColor.swift          — DS.Color tokens + the appearance-aware resolver
  DSText.swift           — DS.Text font tokens
  DSModifiers.swift      — reusable view modifiers (.dsPanel(), .dsImportWell(), …)
  TransportControls.swift — the B+ transport component
```

- **`DS` namespace** — `enum DS {}` with nested groups `DS.Color`, `DS.Space`, `DS.Text`, `DS.Radius`, `DS.Motion`. One greppable home.
- **Appearance-aware color** — each `DS.Color` token is a `Color` backed by `NSColor(name:dynamicProvider:)`. The light and dark values live side by side in `DSColor.swift`; no view branches on `colorScheme`. Dark mode is changed by editing one file.
- **Reusable modifiers and components** — `DSModifiers.swift` carries view modifiers (`.dsPanel()`, `.dsImportWell()`, `.dsSectionHeader()`, etc.); `TransportControls.swift` is the new B+ transport.
- **Retrofit** — every main-window view consumes `DS.*`. No raw `Color(...)`, no magic-number `.padding(8)`, no `.font(.system(size:))` literals remain in the main-window view set.
- **`CueListInspectorMetrics` stays as-is** — it is a layout-contract SSOT (the `NavigationSplitView` column-width contract from the #297 constraint-loop fix), a different concern from visual tokens. The DS layer does not absorb it.

## 5. Design tokens

### 5.1 Color

Strategy: **Restrained, achromatic chrome.** A warm-tinted neutral ramp (OKLCH hue ~85°, chroma ~0.005 — a whisper of warmth, never "cream"). No chromatic accent in the chrome. Cue-type colors are user data and remain the only chroma on screen, so they stay vivid by contrast. The primary-action fill is an `ink` token (near-black in light, near-white in dark), never a blue.

OKLCH is the source of truth; implementation converts to Display P3 / sRGB for the `NSColor` resolver.

| Token | Role | Light (OKLCH) | Dark (OKLCH) |
|---|---|---|---|
| `surface` | main content background | `0.992 0.004 85` | `0.205 0.005 85` |
| `panel` | sidebar / inspector background | `0.972 0.005 85` | `0.235 0.005 85` |
| `surfaceSunken` | preview well, inset areas | `0.962 0.005 85` | `0.170 0.005 85` |
| `border` | hairlines | `0.900 0.005 85` | `0.320 0.006 85` |
| `borderStrong` | emphasized dividers | `0.820 0.006 85` | `0.420 0.007 85` |
| `textTertiary` | hints, disabled | `0.660 0.006 85` | `0.580 0.006 85` |
| `textSecondary` | labels, metadata | `0.520 0.007 85` | `0.720 0.006 85` |
| `textPrimary` | primary text | `0.260 0.006 85` | `0.930 0.004 85` |
| `ink` | primary-action fill | `0.260 0.006 85` | `0.930 0.004 85` |
| `inkOn` | text/icon on `ink` | `0.992 0.004 85` | `0.205 0.005 85` |
| `selection` | selected row fill (achromatic) | `0.915 0.005 85` | `0.300 0.006 85` |

**Selection color** — achromatic, by decision. A selected cue row or media item gets the neutral `selection` fill, not the system accent. This keeps cue-type color the only chroma on screen. The **keyboard focus ring stays system-standard** (it is an accessibility affordance and is untouched).

### 5.2 Typography

SF Pro for chrome, via native semantic styles so Dynamic Type still works (Q1 — stay native). SF Mono for every number and timecode. Tight scale (~1.2 ratio) per the product register.

| Token | Mapping | Use |
|---|---|---|
| `Text.title` | semantic title style, semibold | document / item titles |
| `Text.heading` | semantic body, semibold | section headers |
| `Text.body` | semantic body | control + body text |
| `Text.label` | semantic caption | secondary labels |
| `Text.caption` | 10 pt, uppercase, tracking 0.07em | small caps labels (e.g. "NEXT CUE") |
| `Text.monoHero` | SF Mono 21 pt, semibold | transport current-timecode |
| `Text.mono` | SF Mono 13 pt | readouts |
| `Text.monoSmall` | SF Mono 11 pt | dense numerals |

### 5.3 Spacing, shape, motion

- **`DS.Space`** — 4 pt grid: `xs 4`, `sm 8`, `md 12`, `lg 16`, `xl 24`, `xxl 32`. Applied with rhythm (tight within a group, generous between zones), not uniformly.
- **`DS.Radius`** — `sm 6`, `md 8`, `lg 10`.
- **`DS.Motion`** — `quick 0.15s`, `standard 0.22s`, ease-out only. Motion conveys state, never decoration.

## 6. Structural fixes (the Q8 punch-list)

1. **Remove the in-canvas "OnlyCue" wordmark.** The window title bar already shows the document name via `navigationSubtitle`; an app-name wordmark in the content area is redundant.
2. **Empty state becomes one calm import well.** `DocumentEmptyState` renders a single dashed drop-well (icon, "No media imported", a primary "Import Media…" action, and a one-line "or press ⌘O" hint). The disabled transport, the "0 cues" line, and the placeholder preview box are not shown with no media. Transport and cue UI appear only once media exists.
3. **Cheat-sheet off the canvas.** The persistent monospace hint block (`DocumentShortcutHints`) is removed from the layout. First-run guidance stays in the existing `FirstLaunchSheet`; the full shortcut list moves to a quiet `?` popover (a small button, unobtrusive). This closes the Q5 gap without inventing a feature.
4. **Inspector empty-state no longer clipped.** The cue-inspector empty-state copy is shortened ("Import a media file to start adding cues.") and allowed to wrap within the 240 pt minimum column width.
5. **"Manage Types…" rehomed.** Moved out of the floating bottom-right corner into a deliberate, tidy inspector footer.
6. **Populated transport → B+.** `TransportBar` is replaced by the B+ `TransportControls`: a zoned bar — `[ ⏮ play/pause ⏭ ]  ·  [ current-TC / total ]  ·  [ NEXT CUE value ]` — separated by hairline dividers. Play/pause and previous/next-cue stepping become visible controls (they were keyboard-only). No progress scrubber; the waveform timeline above remains the single seek surface. The existing keyboard shortcuts continue to work unchanged.
7. **Spacing on the 4 pt grid.** Ad-hoc paddings (`VStack(spacing: 12)`, `.padding(.top, 4)`, default `.padding()`) are replaced with `DS.Space` tokens.
8. **Editor-mode switcher goes achromatic.** `EditorModeSwitcher` currently tints the active segment blue / purple / gray (ADR-023 §2.2). Under Quiet Pro, color belongs only to cue data, so the active segment adopts the achromatic `selection` / `ink` treatment used by every other selected control. To preserve ADR-023's at-a-glance mode reading, each segment gains a small leading SF Symbol so the modes are distinguishable by shape rather than hue; **Show mode's glyph is a lock**, reinforcing its read-only nature. This amends ADR-023 (§11).

## 7. Dark mode

Dark mode works **by construction**: every `DS.Color` token resolves per appearance through the `DSColor.swift` provider, and no main-window view branches on `colorScheme`. The ~3 existing hardcoded color literals (`Color.white`, `Color.black`, and the explicit literals in `MediaPreviewStrip.swift`) are migrated to tokens, after which nothing outside the DS layer is appearance-aware.

Light is the **verified** mode: UI-test screenshots are captured in light. A manual dark-mode sanity pass is an explicit acceptance criterion (§9). There is no duplicate dark-mode test suite.

## 8. Testing strategy

TDD per the project convention — failing test first, then implement to green.

- **Token unit tests** (`OnlyCueTests/DesignSystem/`) — each `DS.Color` token resolves to the expected value in each appearance; the OKLCH → sRGB/P3 conversion is correct.
- **Conformance gate** — an automated check (a test that scans the main-window source file set) asserts there are no raw `Color(` initializers, magic-number `.padding(<literal>)` calls, or `.font(.system(size:))` literals in the main-window view set. This is Q8's token-conformance, automated and reviewable.
- **Structural-fix tests** — one XCUITest per punch-list item: the empty state shows the import well and does *not* show the transport, the "0 cues" line, or the cheat-sheet; the inspector empty-state text is present and not truncated; the B+ `TransportControls` exist with correct accessibility identifiers and the play/step buttons are hittable.
- **Accessibility identifiers preserved** — every existing `accessibilityIdentifier` value in the main-window view set is kept (existing UI tests depend on them). New identifiers are added only for new components.
- **Gesture regression check** — per the CLAUDE.md hard rule: click-to-seek, `.sheet(item:)` presentation, context menus, and drag-to-retime must still pass hit-tests after the retheme.
- **Screenshots** — README screenshots are regenerated via XCUITest, real captures, light mode.

## 9. Acceptance criteria

The redesign is done when:

- The conformance gate passes (no raw color/spacing/font literals in the main-window view set).
- All 8 punch-list items have a passing test.
- All pre-existing unit and UI tests still pass; tests are updated only where the redesign intentionally changes user-visible structure.
- A manual dark-mode sanity pass finds no broken contrast or invisible elements on the main window.
- The user signs off on before/after screenshots for the subjective polish layer.

## 10. Build sequence (high-level)

Detailed leaf breakdown is the job of the implementation plan. The dependency order:

1. **Token layer foundation** — `DesignSystem/` group, `DS` namespace, `DSColor` resolver, `DSText`, `DS.Space/Radius/Motion`, token unit tests. Nothing consumes it yet.
2. **Reusable modifiers + `TransportControls`** — `DSModifiers.swift` and the B+ transport component, with their tests.
3. **Per-pane retrofit** — migrate each main-window view to `DS.*` (sidebar, preview/transport center, inspector), one reviewable unit at a time.
4. **Structural fixes** — apply the 8-item punch-list (most land naturally during the retrofit; the empty-state rebuild, cheat-sheet removal, and mode-switcher conversion are explicit steps).
5. **Conformance gate + screenshot regeneration** — add the conformance test, regenerate README screenshots, manual dark-mode pass.

## 11. Proposed ADR

This design introduces a locked, hard-to-reverse decision worth recording in `docs/decisions.md`:

**ADR-024 — Quiet Pro design-token system.** The main window's visual language is a centralized token layer (`OnlyCue/UI/DesignSystem/`); main-window views must not use raw color, spacing, or font literals. Selection highlight is achromatic rather than the system accent, so cue-type color remains the only chroma on screen. Reversal cost: moderate — unwinding the token layer means re-scattering literals across ~15 views.

**ADR-023 amendment.** The editor-mode switcher's blue / purple / gray tints (ADR-023 §2.2) are superseded: the switcher is achromatic, with per-mode SF Symbols replacing the color cue (punch-list item 8). ADR-023's intent — at-a-glance mode reading — is preserved through shape instead of hue. The amendment is recorded against ADR-023.

Both ADR texts are written as part of implementation, not in this spec.

## 12. Risks

- **`List` selection styling.** Achromatic selection on a SwiftUI `List` may require styling the row rather than the list's selection chrome. If the framework resists, the fallback is a custom selected-row background; the keyboard focus ring stays system-standard regardless.
- **Gesture regressions.** The waveform stack has dense overlapping gestures (seek, drag-retime, magnifier, context menu). The retheme must not alter hit-testing — covered by the §8 gesture regression check.
- **Screenshot churn.** Retheming changes every main-window screenshot; existing UI tests that assert on screenshots or layout will need intentional updates, tracked per leaf.
