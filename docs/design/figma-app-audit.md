# Figma ↔ App Audit (Dark Mode)

**Reference:** [OnlyCue Design System · Screens](https://www.figma.com/design/NhH2957iKQ8b581x3gI3Wk/OnlyCue-Design-System?node-id=13-4)
**App version:** branch `dev` @ `c164ec8` (2026-05-24)
**Capture method:** XCUITest screenshot harness (`OnlyCueUITests/*ScreenshotTests.swift`) with `--ui-test-appearance=dark`. Figma side via Figma MCP `get_screenshot`.

## How to read this doc

Each surface has:

- **Figma reference** + **App actual** screenshots, captured at the same point in time.
- A **delta table** with one row per visible difference.
- **Severity**: `structural` (layout / missing element / wrong component) · `pixel-polish` (spacing, radii, weights ≤2px) · `token` (color/typography token mis-applied or missing) · `state` (correct chrome, wrong content state — usually a seed issue, lowest priority).
- **Issue?**: which deltas should become a GitHub issue. State-only deltas usually don't.

The match bar is **pixel-level**: every visible difference is in scope. State-only mismatches are listed but flagged as test-fixture rather than UI bugs.

---

## 1. Settings · Audio

**Figma:** [`321:2200`](https://www.figma.com/design/NhH2957iKQ8b581x3gI3Wk/OnlyCue-Design-System?node-id=321-2200) · 600×645
**App:** `AudioSettingsView.swift` · captured via `AudioSettingsScreenshotTests.test_audioSettings_darkMode_visualBaseline`

| Figma | App |
|---|---|
| ![Figma](audit-screenshots/figma-audio-settings-dark.png) | ![App](audit-screenshots/app-audio-settings-dark.png) |

### Deltas

| # | Severity | Area | Figma | App | Issue? |
|---|---|---|---|---|---|
| 1.1 | structural | Tab order | Audio → Keyboard → Timecode → OSC (left to right) | OSC → Keyboard → Audio (right to left, **Timecode tab absent**) | ✅ yes — missing Timecode tab + wrong order |
| 1.2 | structural | Tab item visual style | Custom dark pill with subtle elevation on selected; icon + label stacked, neutral white text on selected | Apple stock `NSToolbarItem` with system blue accent on selected (`Audio` text in blue, blue tinted icon) | ✅ yes — toolbar style does not match design |
| 1.3 | token | Selected tab color | neutral (`color/text-primary` ≈ `#ebe9e3`) | system `controlAccent` (Apple blue `#0a84ff`) | ✅ yes — should use `color/text-primary` not system accent |
| 1.4 | structural | Content containment | Each section sits inside a rounded "panel" card (`color/panel` fill, ~12 px radius, 1 px `color/border` stroke) — visible around "Enable LTC output" row, "Output device" group, and the channel assignment list | Controls laid directly on the window background with no card containment — flat, no borders, no panel fill | ✅ yes — adopt panel-card pattern |
| 1.5 | pixel-polish | Window padding | ~24 px outer padding around content | ~32 px outer padding (left/right asymmetric — extra space on right) | ✅ yes — tighten and balance |
| 1.6 | pixel-polish | Window width | 600 px | ~916 px (significantly wider than reference) | ✅ yes — constrain default width to match design |
| 1.7 | token | Description text color | `color/text-secondary` (~`#b3afa5`) | Looks like `secondaryLabelColor` (slightly more grey, less warm) | ✅ yes — bind to `color/text-secondary` token |
| 1.8 | state | LTC enabled state | Toggle ON, output device + channel assignment visible | Toggle OFF, lower content hidden | ⚠️ test-fixture — add a second capture seeded with `LTCRouting.isEnabled = true` for full comparison |
| 1.9 | pixel-polish | Toggle visual | Custom indigo (`cue/indigo` ≈ `#5b5bd6`) | System accent blue | ✅ yes — toggle ON-state should be brand indigo (already implemented in some surfaces — verify token binding here) |
| 1.10 | structural | Window chrome | Single close button only (no minimize/zoom), shown top-left | Standard three-button traffic light (red/yellow/grey) | ⚠️ macOS-conventional — recommend KEEPING app behavior; update Figma to show full traffic light. Not an issue. |

### Proposed issue groupings (for `/gh-issue` later)

- **(I-A)** Settings toolbar redesign — tab order, custom pill style, Timecode tab restoration, neutral selection color. Covers 1.1, 1.2, 1.3.
- **(I-B)** Settings panel-card containment — apply card pattern to Settings groups. Covers 1.4.
- **(I-C)** Settings window size + padding — constrain width to 600, balance padding to 24 px. Covers 1.5, 1.6.
- **(I-D)** Settings text token audit — bind secondary text to `color/text-secondary`. Covers 1.7.
- **(I-E)** Settings toggle indigo binding — verify `cue/indigo` token applied. Covers 1.9.
- **(test-fixture)** Add LTC-enabled dark capture variant. Covers 1.8.
- **(figma-side)** Update Figma to show three-button window chrome. Covers 1.10.

---

<!-- TODO: sections 2-18 to be added as captures complete -->
