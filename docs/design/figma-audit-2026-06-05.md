# Figma↔App fidelity audit — 2026-06-05

Coordinate-level audit of the OnlyCue main window against the Figma design system (file `NhH2957iKQ8b581x3gI3Wk`), produced by an 11-agent parallel sweep pulling `get_metadata` per region and diffing against the app code.

Excludes already-decided intentional differences (dark-only ADR-029, SMPTE-vs-decimal ADR-028, achromatic chrome ADR-024, compact durations, selected-row cue-type tint).

**Totals:** 14 high · 32 medium · 42 low (88 deltas across 11 regions)


## sidebar

_The app reproduces the right elements (MEDIA header, icon + name + compact duration rows) and honors the ADR carve-outs, but the structural fidelity is off: it relies on a default SwiftUI List instead of the Figma's fixed 30pt rows on a 32pt pitch with an inset rounded-pill selection, the pane is narrower (200 vs 240), the header insets are halved, and several spacing/font values do not map to the Figma measurements._

- **[HIGH] ItemRowView instances (318:1241‑1248)** (layout)
  - Figma: Each row is a fixed 30pt-tall cell on a 32pt vertical pitch (rows at y=33,65,97,… = 30pt + 2pt gap), left-inset 8pt from the 8pt content frame (16pt from pane edge), 224pt wide
  - App: Rows are emitted inside a default SwiftUI List with no .frame(height:) and no listRowInsets — ItemListPane.swift:94-110 / ItemRowView.swift:12. macOS List default row height (~24-28pt variable) and default insets do not match the 30pt fixed height / 32pt pitch.
  - Fix: Pin each row to height 30 and control spacing to a 2pt gap (e.g. .frame(height: 30), .listRowInsets, .listRowSeparator(.hidden)), or build the list with an explicit 30pt-row layout so the cadence matches Figma.
- **[HIGH] Selected row background (see 318:1242 'Dialogue — Scene 2')** (layout)
  - Figma: Selection is an inset rounded-rectangle pill: it sits inside the 8pt content frame (≈8pt horizontal inset from the pane edge) with rounded corners (~6pt), filling the 30pt row
  - App: Selection comes from List's default selection styling (full-bleed rectangle, no inset, no corner radius); no custom selected-row background shape in ItemRowView — ItemRowView.swift:12-60
  - Fix: Render the selected row's background as an inset RoundedRectangle (corner ≈ DS.Radius.sm=6) filled with DS.Color.selection, inset ~8pt horizontally, rather than relying on List's default selection chrome.
- **[MEDIUM] Sidebar · ItemListPane (318:1238)** (size)
  - Figma: Sidebar fixed width 240pt
  - App: frame(minWidth: 200) with no ideal/fixed width — ItemListPane.swift:28
  - Fix: Set the pane's preferred width to 240 (e.g. minWidth: 240 or an explicit frame/navigationSplitView column width) so it matches the Figma sidebar instead of collapsing toward 200.
- **[MEDIUM] MEDIA section header (318:1239 / text 318:1240)** (spacing)
  - Figma: Header frame inset 8pt from pane edge and the 'MEDIA' text inset a further 8pt (≈16pt total from the pane's left edge); header band ~23pt tall with text vertically centered (text y=6 in a 23pt frame)
  - App: Header padded only .horizontal DS.Space.sm=8 and .top DS.Space.sm=8 — ItemListPane.swift:18-19. That yields ~8pt left inset (vs 16pt) and a top-aligned, not band-centered, label.
  - Fix: Increase the header's leading inset to ~16pt to align with the row text column, and give the header a ~23pt band with the label vertically centered to match the Figma frame.
- **[MEDIUM] Row left inset / text column alignment** (spacing)
  - Figma: Row content frame begins 16pt from the pane edge (8pt frame + 8pt), and the icon+text column aligns under that 16pt gutter so the MEDIA label and the file names share a left edge
  - App: List rows inherit List's default leading inset (not 16pt) and the icon sits at the row's leading edge with HStack spacing DS.Space.sm — ItemRowView.swift:13. The icon/text column does not provably line up with the 16pt Figma gutter.
  - Fix: Set listRowInsets to a leading inset of 16pt so the icon column and the MEDIA header share the same left edge as in Figma.
- **[LOW] Media name label** (font)
  - Figma: File-name label appears as standard body weight (~13pt regular) in primary text color
  - App: item.resolvedName uses the inherited default font (no DS.Text token applied) — ItemRowView.swift:18-20. It is not bound to a DS typography token, so it is not guaranteed to match DS.Text.body / primary color.
  - Fix: Bind the name to .font(DS.Text.body) and .foregroundStyle(DS.Color.textPrimary) explicitly so it tracks the design system rather than SwiftUI defaults.
- **[LOW] Duration label** (font)
  - Figma: Right-aligned compact duration (e.g. 3:42) in small tertiary monospaced grey
  - App: Uses DS.Text.label (Font.caption ≈11pt) + textTertiary + monospacedDigit — ItemRowView.swift:25-28. Figma's number looks closer to ~11pt mono which is roughly consistent, but DS.Text.label is the proportional caption with only digit monospacing, not a fully monospaced face.
  - Fix: If the Figma duration is fully monospaced, use DS.Text.monoSmall (11pt mono) instead of caption+monospacedDigit for an exact match; otherwise this is acceptable.
- **[LOW] Video row icon** (other)
  - Figma: Video clips (Projection — Storm.mp4, Set Change.mov, Curtain Call.mov) use a rounded rectangle / clapboard-style glyph, not the SF 'film' sprocket-strip icon
  - App: icon returns 'film' for .video — ItemRowView.swift:62-66
  - Fix: Confirm the Figma video glyph; if it is the rounded-rectangle/'rectangle.on.rectangle' style shown, switch the video icon to match rather than 'film'.
- **[LOW] Inline pencil edit button** (extra)
  - Figma: Figma rows show only icon + name + duration; no inline edit affordance is drawn in the sidebar rows
  - App: Each row renders a trailing pencil Button (22×22) — ItemRowView.swift:31-49
  - Fix: Intentional per Audit §13 (discoverability + XCUITest). Keep, but consider hiding it until row hover so the resting state matches the cleaner Figma row.

## switcher-bar

_The EditorModeSwitcher matches Figma structurally (3 icon+label segments, ink active pill on a sunken track) but every spacing/radius/size token is off by 1-2pt from the Figma spec, the icon is undersized, the label font uses a Dynamic-Type body instead of the fixed 12pt, and inactive labels render regular weight where Figma uses semibold throughout._

- **[MEDIUM] Segment pill / vertical padding** (spacing)
  - Figma: py-[5px] (5pt top/bottom inside each segment)
  - App: DS.Space.xs = 4pt at EditorModeSwitcher.swift:44 (.padding(.vertical, DS.Space.xs))
  - Fix: Increase to 5pt vertical padding so the active pill is 31pt tall as in Figma rather than running short.
- **[MEDIUM] Segment icon (ic-cue / ic-lyric / ic-show)** (size)
  - Figma: Icon frame size-[13px] (13x13)
  - App: SF Symbol .font(.system(size: 10, weight: .medium)) at EditorModeSwitcher.swift:36 — glyph ~10pt, noticeably smaller than the 13pt Figma icon
  - Fix: Bump the symbol size toward 13pt (or imageScale) so the leading icon reads at the Figma weight; current 10pt makes the mode glyph feel undersized next to the 12pt label.
- **[MEDIUM] Segment label font** (font)
  - Figma: Inter Semi Bold 12px, fixed
  - App: DS.Text.body = Font.body at EditorModeSwitcher.swift:39 — system body (~13pt at default Dynamic Type, and scales with accessibility sizes)
  - Fix: Use a fixed ~12pt label (e.g. DS.Text.label / a 12pt token) instead of Font.body so the segment text matches the 12px spec and does not grow the control under Dynamic Type.
- **[MEDIUM] Inactive segment label weight** (font)
  - Figma: All three labels are font-semibold (active and inactive both Semi Bold); only color differs (ink-on vs text-secondary)
  - App: fontWeight(isActive ? .semibold : .regular) at EditorModeSwitcher.swift:40 — inactive segments render regular weight
  - Fix: Render all labels semibold and convey active state via background + foreground color only (matching Figma), rather than dropping inactive labels to regular weight.
- **[LOW] EditorModeSwitcher / container padding** (spacing)
  - Figma: Track inner padding p-[3px] (3pt all sides)
  - App: DS.Space.xs/2 = 2pt at EditorModeSwitcher.swift:20 (.padding(DS.Space.xs / 2))
  - Fix: Use 3pt of track padding (e.g. .padding(DS.Space.xs - 1) or an explicit 3) to match Figma p-[3px].
- **[LOW] EditorModeSwitcher / track corner radius** (size)
  - Figma: rounded-[8px] (radius/md = 8)
  - App: DS.Radius.sm + 1 = 7pt at EditorModeSwitcher.swift:21
  - Fix: Use DS.Radius.md (8) for the track background instead of DS.Radius.sm + 1.
- **[LOW] Segment pill / horizontal padding** (spacing)
  - Figma: px-[11px] (11pt left/right inside each segment)
  - App: DS.Space.md = 12pt at EditorModeSwitcher.swift:43 (.padding(.horizontal, DS.Space.md))
  - Fix: Reduce to 11pt; off by 1pt per side, widens the whole control.
- **[LOW] Segment pill / icon-to-label gap** (spacing)
  - Figma: gap-[5px] between icon and text
  - App: DS.Space.xs = 4pt at EditorModeSwitcher.swift:34 (HStack(spacing: DS.Space.xs))
  - Fix: Use 5pt icon/label gap to match Figma gap-[5px].
- **[LOW] Segment pill / corner radius** (size)
  - Figma: rounded-[6px] (radius/sm = 6)
  - App: DS.Radius.sm - 1 = 5pt at EditorModeSwitcher.swift:46
  - Fix: Use DS.Radius.sm (6) for the active pill instead of DS.Radius.sm - 1.

## preview-waveform

_The app's waveform region is structurally much shorter than Figma's tall full-pane well, the time ruler is positioned/proportioned differently (and below the waveform conceptually rather than as a top band), and several measured details (well inset, ruler band height, tick heights, separator line, lyric-chip lane height) diverge from the 602pt spec._

- **[HIGH] Waveform Well (318:1253) / preview ZStack** (size)
  - Figma: Waveform Well is 648x602pt and fills the entire 614pt-tall Preview Area; the waveform graphic itself (318:1254) is 576pt tall.
  - App: For VIDEO the timeline/waveform is pinned to a fixed 100pt (160pt with breakdown) at PreviewPane.swift:108; the preview ZStack only gets .frame(minHeight: 180) at PreviewPane.swift:29. The whole pane is far shorter than the 602pt Figma well and does not fill the available height.
  - Fix: Let the waveform/timeline expand to fill the pane (maxHeight: .infinity) instead of a fixed 100pt, so the well approaches the Figma 602pt full-height proportion. At minimum raise the fixed audio/video waveform height substantially.
- **[HIGH] Preview Area frame (318:1252)** (layout)
  - Figma: Figma Preview Area is 680pt wide x 614pt tall (roughly square-ish, tall). The waveform is the dominant vertical element.
  - App: The preview pane lives in a VStack(spacing:12) in DocumentView.mainPane (DocumentView.swift:97) sharing vertical space with LTC strip + TransportControls, and PreviewPane only guarantees minHeight 180. Net visible waveform proportion is a thin band, not the tall dominant block in Figma.
  - Fix: Allocate the lion's share of mainPane vertical space to PreviewPane (it already has the EditorModeSwitcher on top); ensure the inner waveform grows rather than being capped.
- **[HIGH] Time Ruler (318:1271)** (layout)
  - Figma: Ruler is a dedicated 648x22pt band pinned at the TOP of the waveform area (y=26, just under the cue-marker flag row), with a 1px separator line (318:1256) at y=25.5 dividing it from the waveform. Labels are above ticks (text y=1, ticks below).
  - App: Ruler is drawn as a Canvas overlay across the FULL waveform height (WaveformContainer+Overlays.swift:24-34) with a hardcoded topInset of 24pt (line 39); ticks are drawn growing DOWN from y=24 and labels drawn at the tick top. There is no dedicated 22pt band and no separator line below the ruler.
  - Fix: Render the ruler as a fixed ~22pt top band with a 1px borderStrong separator beneath it (Figma 318:1256), matching the y=26 placement, rather than a free-floating overlay keyed off a magic 24pt inset.
- **[MEDIUM] Ruler separator line (318:1256)** (missing)
  - Figma: A 648x1pt rounded-rectangle separator at y=25.5 sits between the ruler band and the waveform.
  - App: No horizontal separator line between ruler and waveform exists in WaveformContainer+Overlays.swift drawTimeRuler.
  - Fix: Add a 1pt borderStrong horizontal divider at the bottom of the ruler band.
- **[MEDIUM] Waveform Well horizontal inset (318:1253)** (spacing)
  - Figma: The well is inset 16pt from the Preview Area left/right edges (x=16, width 648 inside 680).
  - App: WaveformContainer.loaded applies .padding(.horizontal, 8) (WaveformContainer.swift:82); the surrounding preview ZStack adds no explicit horizontal inset. Effective inset is 8pt vs Figma 16pt.
  - Fix: Use a 16pt horizontal inset for the waveform well to match Figma (DS.Space would need md+; currently sm=8).
- **[MEDIUM] Lyric chip lane (318:1263 LyricChip Compact)** (size)
  - Figma: Lyric chips are 18pt tall compact pills pinned at y=576 (bottom of the 602pt well), with 13pt text inset 6pt left and 2.5pt top.
  - App: Lyrics lane is a bottom-pinned VStack with Spacer (WaveformContainer+Overlays.swift:85-103) via LyricsLaneView; not verified to the 18pt compact-chip height / 6pt+2.5pt text inset here. Because the overall well is ~100pt not 602pt, the lane occupies a disproportionate share.
  - Fix: Confirm LyricsLaneView chips are 18pt tall with 6pt/2.5pt text padding; main fix is restoring well height so the lane is a thin bottom strip as in Figma.
- **[MEDIUM] Playhead Time badge (318:1300)** (size)
  - Figma: Playhead time readout is an 81x19pt badge at y=52 (just below the ruler band), with the playhead handle (318:1302, 12x8pt) at top y=2 and a 1px full-height playhead line (318:1262).
  - App: Playhead is WaveformPlayheadVisual (WaveformContainer.swift:161-173), not read here; badge dimensions/position relative to the ruler band not verified. With the compressed well height the badge's y=52 anchor below a 22pt ruler band cannot be reproduced.
  - Fix: Position the playhead time badge just under the ruler band (~y=52 in the 602pt well) and confirm an ~81x19pt badge + 12x8pt handle; depends on restoring well height.
- **[LOW] Ruler tick heights (318:1272 minor / 318:1286 major)** (size)
  - Figma: Minor ticks are 5pt tall (y=17..22), major ticks 9pt tall (y=13..22); ticks are bottom-aligned to the band baseline (y=22).
  - App: drawTimeRuler uses tickHeight 4pt minor / 8pt major (WaveformContainer+Overlays.swift:43) and draws them downward from topInset (top-aligned), not bottom-aligned to a band.
  - Fix: Use 5pt minor / 9pt major and bottom-align ticks to the ruler band baseline.
- **[LOW] Ruler major label cadence** (text)
  - Figma: Major labels every 30s (00:00, 00:30, 01:00 ... at x=0,96,192...). Minor ticks every ~16s between, i.e. 2 minors per major (major every 3rd tick visually here, ticks at 32px spacing, majors at 96px = every 3rd).
  - App: WaveformRulerTicks marks isMajor on every 5th tick (step % 5 == 0, WaveformRulerTicks.swift:30). With the chosen bucket this yields a different major spacing than Figma's every-30s/every-3rd-tick cadence.
  - Fix: Align major cadence so labelled majors land on round 30s/60s boundaries (every 3rd tick at this scale) rather than mechanically every 5th tick.
- **[LOW] Cue markers (318:1303 CueMarker)** (size)
  - Figma: Cue markers are 18x20pt flags pinned at the TOP of the well (y=3), occupying a ~23pt flag zone above the ruler.
  - App: drawTimeRuler comments assume flags occupy the top ~22pt (WaveformContainer+Overlays.swift:38) which roughly matches 23pt; marker geometry is in CueMarkersOverlay (not read here). Flag zone height (~23pt) appears consistent but should be verified against 20pt marker height + 3pt top offset.
  - Fix: Verify CueMarkersOverlay renders 18x20pt markers at a 3pt top offset to match the 23pt flag zone.

## ltc-strip

_The LTC strip is structurally faithful — 34pt height, 150pt panel header, sunken ruler with bottom-aligned major/minor ticks (9/5pt, 2pt inset, border-strong) and 9pt tertiary mono labels all match Figma — but the header label uses a monospaced font where Figma specifies the sans (Inter) body font, and several header metrics (icon size, internal gap, horizontal padding, ruler left inset) are off by a few points._

- **[MEDIUM] Header label (I318:1308;35:20 "LTC · master.wav")** (font)
  - Figma: Inter Regular 11px (sans body font), color text-secondary
  - App: DS.Text.monoSmall = Font.system(size: 11, design: .monospaced) at LTCStrip.swift:43 (DSText.swift:15)
  - Fix: The clip-name label is sans in Figma, not monospaced. Use the regular 11pt sans body token (e.g. DS.Text.small) instead of DS.Text.monoSmall for the header label; keep mono only for the ruler tick labels.
- **[MEDIUM] Ruler frame left inset (I318:1308;35:21)** (spacing)
  - Figma: pl-[8px] — the tick lane starts 8pt after the header edge, so the first tick/label is inset from the header boundary
  - App: ruler GeometryReader starts flush at the HStack boundary with no leading padding (LTCStrip.swift:55-63); ticks computed across full size.width from x=0
  - Fix: Add an 8pt leading inset to the ruler lane (or offset the tick content x by 8pt) so the first tick column doesn't butt directly against the panel header, matching Figma's pl-8 ruler frame.
- **[LOW] Header frame internal gap (I318:1308;35:16)** (spacing)
  - Figma: gap-[6px] between speaker icon and label
  - App: HStack(spacing: DS.Space.sm) = 8pt at LTCStrip.swift:33
  - Fix: Use DS.Radius.sm-equivalent 6pt spacing (Figma gap is 6, not 8). Introduce/usе a 6pt spacing value for the icon↔label gap.
- **[LOW] Header frame horizontal padding (I318:1308;35:16)** (spacing)
  - Figma: px-[10px] (10pt left and right inset)
  - App: .padding(.horizontal, DS.Space.sm) = 8pt at LTCStrip.swift:48
  - Fix: Header horizontal padding should be 10pt, not 8pt — use DS.Space.md (12) is too much; add a 10pt inset to match the Figma frame padding.
- **[LOW] Speaker icon (I318:1308;35:17 ic-spkr)** (size)
  - Figma: 17pt wide × 14pt tall (non-square)
  - App: .frame(width: 18, height: 18) at LTCStrip.swift:36
  - Fix: Icon glyph box in Figma is 17×14, not 18×18. Reduce the frame to roughly 17×14 (or let the SF Symbol size naturally to ~14pt height) so the icon isn't slightly oversized/too square.
- **[LOW] Major tick label vertical position (I318:1308;35:114..118)** (spacing)
  - Figma: labels positioned top-[4px] from the strip top
  - App: context.draw(text, at: CGPoint(x: ..., y: 3), anchor: .topLeading) at LTCStrip.swift:93
  - Fix: Draw the tick labels at y=4 to match Figma's top-[4px] (currently 3).
- **[LOW] Tick spacing / first major label position** (layout)
  - Figma: tick columns are 16pt apart (w-16 cells); major labels sit at left 170,266,362,458,554 → 96pt apart, every 6th tick is major (h-9), giving 30s major / 5s minor cadence at this zoom
  - App: tick positions are data-driven from LTCTickGenerator across size.width (LTCStrip.swift:67-75); spacing depends on duration/width rather than a fixed 16pt/96pt grid
  - Fix: No code change required if LTCTickInterval.pick reproduces the same major/minor cadence (every 6th tick major, ~30s majors) at typical widths; verify against the Figma 16pt-tick / 96pt-major grid to ensure the visual rhythm matches rather than relying on the screenshot alone.

## transport-bar

_The transport zones, fonts, and readout structure are close, but the app renders the bar as a fully-bordered rounded card with full-height dividers and a right-pushed next-cue zone, whereas Figma is a flat strip with only a top hairline, fixed 26pt dividers, and the next-cue group sitting immediately after the readout on a uniform 16pt gap; button sizes/styling also diverge._

> **Resolved (issue #506):** prev/next skip buttons are now box-less glyphs (only the primary play/pause keeps its filled `DS.Color.ink` button), the inter-zone hairline dividers are vertically inset, and the next-cue value drops its redundant `Next:` prefix (the zone's `NEXT CUE` caps header already names it). **Intentional divergence:** the main readout and total stay SMPTE `HH:MM:SS:FF` rather than Figma's decimal `00:01:30.470 / 03:24.0` — frame precision is required for a timecode/lighting tool (per ADR-028, SMPTE-vs-decimal).

- **[HIGH] TransportControls container (318:1310)** (layout)
  - Figma: Flat bar: top border ONLY (border-t, color/border), background color/panel, NO corner radius, NO side/bottom borders. Padding px-16 py-10. Height 50.
  - App: Wrapped in a rounded card: .background(panel) + .overlay(RoundedRectangle(cornerRadius: DS.Radius.md=8).strokeBorder(border)) + .clipShape(RoundedRectangle md) at TransportControls.swift:39-41. Full border on all four sides + 8pt rounded corners.
  - Fix: Replace the rounded-card background/overlay/clipShape with a flat panel background plus a single top hairline (e.g. .background(DS.Color.panel) and an .overlay(alignment:.top){ DS.Color.border.frame(height:1) }). Drop the cornerRadius/clipShape.
- **[HIGH] Next-cue zone placement** (spacing)
  - Figma: Container uses a uniform gap-16 across all zones; the Next Cue group sits immediately after the readout divider on the same 16pt gap (no large flexible gap). Bar content is left-grouped.
  - App: HStack inserts Spacer(minLength: DS.Space.md) before the next-cue divider (TransportControls.swift:35), pushing the next-cue zone to the far right edge of the bar.
  - Fix: Remove the Spacer so the next-cue divider + zone follow the readout on the same fixed gap, matching Figma's left-grouped, uniform-16pt layout (or move the spacer only if a trailing layout is intended — but Figma is left-grouped).
- **[MEDIUM] Zone dividers (I318:1310;34:15 / 34:19)** (size)
  - Figma: Each divider is a 1px-wide rectangle that is 26pt tall (h-26 w-px), vertically centered — does not span the full bar height.
  - App: divider = DS.Color.border.frame(width:1).frame(maxHeight:.infinity) at TransportControls.swift:50 — spans the full bar height.
  - Fix: Constrain the divider height to 26pt instead of .infinity, e.g. .frame(width: 1, height: 26).
- **[MEDIUM] Next Cue VStack alignment (I318:1310;34:20)** (layout)
  - Figma: items-start — 'NEXT CUE' label and the countdown value are left-aligned.
  - App: VStack(alignment: .trailing ...) at TransportControls.swift:156 — right-aligned.
  - Fix: Change VStack alignment to .leading to match Figma's left-aligned next-cue stack.
- **[MEDIUM] Side icon buttons prev/next (I318:1310;34:7 / 34:14)** (size)
  - Figma: 28pt wide x 26pt tall, transparent background (rgba(0,0,0,0)), rounded-6, NO visible stroke/border.
  - App: 30x30 with DS.Color.surface fill and a visible RoundedRectangle.strokeBorder(border) (TransportControls.swift:82-88). Square 30x30, opaque surface fill + border.
  - Fix: Size side buttons to 28x26, use a clear/transparent background, and drop the border stroke for non-primary buttons to match Figma's bare icon buttons.
- **[MEDIUM] Per-zone padding** (spacing)
  - Figma: Single container padding px-16 py-10; zones separated only by the 16pt gap, no extra inner horizontal/vertical padding per zone.
  - App: controlZone adds .padding(.horizontal lg=16, .vertical md=12) (TransportControls.swift:68-69) and readoutZone/nextCueZone add .padding(.horizontal lg=16) (lines 120,171); next-cue also .vertical md=12. This compounds with the inter-zone Spacer/gaps and yields larger internal padding than Figma's flat py-10.
  - Fix: Move padding to a single container (.padding(.horizontal,16).padding(.vertical,10)) and remove the per-zone horizontal/vertical paddings, relying on the inter-zone gap (16) for separation.
- **[MEDIUM] Inter-zone gap** (spacing)
  - Figma: Container gap-16 between control / divider / readout / divider / next-cue.
  - App: Outer HStack(spacing: 0) at TransportControls.swift:31; separation comes entirely from per-zone .horizontal padding (16 each side = up to 32 between zones) plus the Spacer, not a uniform 16.
  - Fix: Use HStack(spacing: 16) and remove the per-zone horizontal padding so adjacent zones sit exactly 16pt apart as in Figma.
- **[LOW] Primary play/pause button (I318:1310;34:10)** (size)
  - Figma: 34pt wide x 28pt tall, ink fill, rounded-6.
  - App: 34x34 (square) ink fill, rounded sm=6 (TransportControls.swift:82). Height 34 vs Figma 28.
  - Fix: Set the primary button frame to 34x28 instead of 34x34.
- **[LOW] Control-zone button gap (I318:1310;34:3)** (spacing)
  - Figma: gap-6 between the three transport buttons.
  - App: HStack(spacing: DS.Space.sm = 8) at TransportControls.swift:56.
  - Fix: Use 6pt spacing between transport buttons (no exact DS token; closest is xs=4 — consider an explicit 6 or add a token).

## inspector-cuelist

_The structural skeleton matches Figma well (clock header → CUES section header → column header → row list → Manage Types footer all present and in the right order), but several proportion/sizing deltas exist: the clock font is smaller than Figma's 40pt-tall readout, the column header has a leading swatch placeholder column that shifts TIME/#/NAME/FADE alignment relative to the rows, and a few spacing/padding values diverge from the Figma 18pt edge inset and fixed row/section heights._

- **[HIGH] Column Header — leading swatch placeholder (318:1320)** (layout)
  - Figma: Column header reserves an 8x8 swatch slot at x=18 BEFORE the TIME label (TIME starts at x=34). So the header's first column is a color-swatch gutter aligned with the row swatches.
  - App: headerRow (CueListPane.swift:220-250) has NO leading swatch/gutter — it starts directly with Text("Time"). Rows (CueRowView.swift:35) DO carry an 8pt CueColorSwatch plus DS.Space.xs spacing, so the header columns are offset left relative to the row columns and do not line up with the row swatch gutter.
  - Fix: Add a matching leading swatch-width spacer (8pt swatch + same DS.Space.xs spacing / leading padding) to headerRow so TIME/#/NAME/FADE align with the row text columns, as Figma's x=34 TIME does.
- **[MEDIUM] PlayheadClockHeader / clock text (318:1313)** (size)
  - Figma: Clock readout text node is 40pt tall (x=80.5 w=199), implying ~34px semibold monospaced glyphs; the whole header frame is 65pt tall.
  - App: Font is .system(size: 30, weight: .semibold, design: .monospaced) at PlayheadClockHeader.swift:18, with .minimumScaleFactor(0.5) so it shrinks further under width pressure.
  - Fix: Bump the clock font toward ~34pt to match the 40pt text-node cap height; keep minimumScaleFactor for compression but raise the base size so at full width it reads as large as Figma.
- **[MEDIUM] Section / row horizontal edge inset** (spacing)
  - Figma: Content left inset is 14-18pt: CUES at x=14, column-header swatch at x=18, cue rows inset x=6 (row container) with swatch at ~x=18 inside.
  - App: rowHorizontalPadding = 8 (CueListPane.swift:8) for header/section; cue rows use .padding(.leading, DS.Space.xs/2)=2 (CueRowView.swift:69). Edge insets are ~8pt and ~2pt, narrower than Figma's 14-18pt.
  - Fix: Increase the shared horizontal padding toward ~14-18pt so CUES, the column header, and the row swatch gutter all sit at the Figma 14-18pt inset.
- **[MEDIUM] Cue row height / pitch (318:1326..1331)** (size)
  - Figma: Each CueRowView instance is 30pt tall with a 32pt pitch (2pt inter-row gap).
  - App: Row height is intrinsic: HStack(spacing: DS.Space.xs) with .padding(.vertical, DS.Space.xs/2)=2 (CueRowView.swift:32,70) over 13pt body/mono text ≈ ~17pt, well under the Figma 30pt. List default row spacing also differs from the 2pt gap.
  - Fix: Give rows a minimum ~30pt height (e.g. .frame(minHeight: 30) or larger vertical padding) so each cue row matches the Figma 30pt row and reads less cramped.
- **[MEDIUM] Inspector Footer / Manage Types button (318:1332, 318:1333)** (size)
  - Figma: Footer frame is 48pt tall; the Manage Types button is 127x28, right-aligned at x=221 (12pt from the 360 right edge), 10pt from footer top.
  - App: CueListFooter (CueListFooter.swift:8-23) is an HStack with Spacer + .bordered .controlSize(.small) button, padded .horizontal rowHorizontalPadding(8) / .vertical DS.Space.xs(4). Footer height ≈ button(~22pt small) + 8pt ≈ 30pt, shorter than 48pt; horizontal inset 8pt vs 12pt; small control size yields a button shorter than 28pt.
  - Fix: Pin footer to ~48pt height, use ~12pt horizontal inset, and size the button toward 28pt tall (regular controlSize or explicit height) to match Figma.
- **[LOW] PlayheadClockHeader frame height (318:1312)** (size)
  - Figma: Header frame is exactly 65pt tall with the divider pinned at y=64 (bottom edge).
  - App: Header height is implicit from content: VStack(spacing:2) of clock + Divider, with .padding(.top,4) and Divider .padding(.top,6) (PlayheadClockHeader.swift:16,40-43). No fixed 65pt frame, so actual height is driven by the 30pt font + paddings (~ <65pt).
  - Fix: Pin the header to a 65pt height (or increase top/bottom padding) so the clock block occupies the Figma vertical budget instead of collapsing to font height.
- **[LOW] Framerate caption (318:1315)** (spacing)
  - Figma: Framerate label sits at x=315, y=10 — top-right, ~10pt below the frame top and ~14pt from the right edge (frame is 360 wide).
  - App: .overlay(alignment: .topTrailing) on the clock text (PlayheadClockHeader.swift:34-38) with no inset, so it pins to the clock text's trailing edge / top, not the header frame's 14pt-from-edge corner.
  - Fix: Anchor the framerate caption to the header frame's top-trailing with ~10pt top / ~14pt trailing padding rather than to the clock text's bounds.
- **[LOW] Column header text content — TIME/#/NAME/FADE** (text)
  - Figma: Labels read TIME, #, NAME, FADE (uppercase column headers).
  - App: headerRow uses Text("Time"), Text("#"), Text("Name"), Text("Fade") rendered uppercase via .dsSectionHeader() tracking (CueListPane.swift:221-242). Visually uppercase — matches.
  - Fix: No change needed; confirm dsSectionHeader applies .textCase(.uppercase) so the labels render as TIME/NAME/FADE.
- **[LOW] Column header height (318:1319)** (size)
  - Figma: Column Header frame is 20pt tall (y=102 to 122).
  - App: headerRow uses .padding(.vertical, DS.Space.sm) = 8pt top+bottom around caption text (CueListPane.swift:255), giving ~10pt text + 16pt padding ≈ 26pt, taller than Figma's 20pt.
  - Fix: Reduce header vertical padding (e.g. DS.Space.xs) so the column header row is ~20pt tall.
- **[LOW] CUES section header height (318:1316)** (size)
  - Figma: Inspector Header (CUES / count) frame is 37pt tall.
  - App: CueListSectionHeader (CueListSectionHeader.swift:23-25) pads .top DS.Space.sm(8) + .bottom DS.Space.xs(4) over ~11pt caption ≈ 23pt, shorter than the Figma 37pt.
  - Fix: Increase the section-header vertical padding (or set a ~37pt min height) so the CUES band matches the Figma height.
- **[LOW] FADE column values — unit suffix** (text)
  - Figma: Fade column shows values like "1.5 s", "2.0 s" with a trailing unit.
  - App: fadeCell renders cue.fadeTime.columnDisplay (CueRowView.swift:138) which carries the " s" unit — matches Figma.
  - Fix: No change needed; matches.
- **[LOW] Selected-row tint / highlight** (color)
  - Figma: Selected row (row 2 "Verse 1") shows a subtle achromatic highlight band.
  - App: rowBackground (CueListPane+RowBackground.swift:23-31) uses DS.Color.selection (achromatic) for the selected row plus cue-type tint per the ADR-024 carve-out — matches the achromatic-selection intent.
  - Fix: No change needed; matches the documented selection-tint behavior.

## titlebar

_The app relies on the stock macOS document titlebar (window filename as title, navigationSubtitle for the second line), which structurally matches Figma's two-line centered title/subtitle and standard traffic-light + sidebar-toggle chrome; the main fidelity gap is semantic — Figma's subtitle is the editor mode ("Cue Mode") whereas the app shows the active media item's name — plus there is no custom typography/weight control over the system-rendered title strings._

- **[HIGH] Cue Mode (subtitle text, node 318:1236)** (text)
  - Figma: Second titlebar line reads "Cue Mode" — the current editor mode label, x=613 y=29, ~11pt grey, centered under the title.
  - App: DocumentView.swift:53 binds .navigationSubtitle to document.model.activeItem?.resolvedName — it shows the active MEDIA ITEM's name, not the editor mode. The editor mode (EditorMode.cue/.lyric, DocumentView.swift:34) is never surfaced in the titlebar subtitle.
  - Fix: Set .navigationSubtitle to the editor-mode display string (e.g. editorMode == .cue ? "Cue Mode" : "Lyric Mode") to match Figma, or add the mode as a prefix; reconsider whether the media item name belongs elsewhere (it already appears in the sidebar/preview).
- **[MEDIUM] Set List — Act I (title text, node 318:1235)** (text)
  - Figma: First titlebar line is the project/set-list name "Set List — Act I", bold ~14pt, x=592 y=12.
  - App: No explicit .navigationTitle is set in DocumentView.swift; the title falls back to the DocumentGroup window title, which is the .cuelist FILE NAME (OnlyCueApp.swift:22). Figma's title is a human set-list name with an em-dash act qualifier, implying a richer project/act naming concept that the app does not model in the titlebar.
  - Fix: If a set-list/act name distinct from the filename is intended, add an explicit .navigationTitle bound to that model field; otherwise confirm the filename-as-title is the accepted substitution and document it (ADR) so the em-dash "set list — act" structure isn't expected.
- **[LOW] Title typography (line 1)** (font)
  - Figma: Title is ~14pt semibold/bold, white; subtitle ~11pt regular grey — a deliberate weight/size hierarchy between the two lines.
  - App: Both lines are rendered by AppKit's stock document titlebar (no styling hook in DocumentView.swift:53 / OnlyCueApp.swift); system uses NSWindow's default ~13pt title and ~11pt subtitle. The app has no control over title weight/size, so the exact Figma 14pt-bold title cannot be guaranteed and DS.Text tokens (DSText.swift) are not applied here.
  - Fix: Accept the system titlebar typography (matching macOS conventions) unless pixel-exact 14pt-bold is required; if it is, a custom NSToolbar/centered title accessory would be needed — note this is the same deferred NSToolbarDelegate work referenced in OnlyCueApp.swift:35-36.
- **[LOW] Titlebar height / chrome layout** (layout)
  - Figma: TitleBar frame is 52pt tall (node 318:1229) with traffic lights vertically centered at y=20 (12pt dots) and the sidebar-toggle glyph at x=104.
  - App: Height and control positions come from the stock macOS title bar, not modeled in code. Standard macOS unified titlebar is ~52pt with toolbar, so this matches by default; the sidebar toggle is provided automatically by NavigationSplitView (DocumentView.swift:37). No delta in control presence/placement, just no explicit control.
  - Fix: No change needed — system chrome already reproduces the 52pt height, traffic-light placement, and sidebar-toggle position; verify visually that the unified toolbar height is not reduced by a compact-toolbar setting.

## lyric-inspector (Figma 318:1469 — Inspector · LyricsInspectorPane)

_The major sections and tokens are present and broadly faithful, but two structural deltas stand out: the app injects a "Set from Playhead" button into the Sync Offset row that does not exist in the Figma layout, and the placed-line rows lack the fixed timestamp column that Figma uses to align all lyric text at a common left edge._

- **[HIGH] Sync Offset row (318:1473) — Set from Playhead button** (extra)
  - Figma: Row 318:1473 is 42pt tall and contains only the 'Sync Offset' label (x=14) and the boxed offset field (Sync Offset Field 318:1475 at x=226, w=120, h=26). There is NO inline button in this row.
  - App: LyricsOffsetControl.swift:25 adds a Button("Set from Playhead") between the label Spacer and the field inside the same HStack.
  - Fix: Remove the inline 'Set from Playhead' button from the offset row (move it elsewhere, e.g. a context action or below), so the row matches Figma: label left, 120pt boxed field right-aligned. Or confirm the affordance is intentionally app-only and document it.
- **[HIGH] Placed rows (318:1490 etc.) — timestamp column alignment** (layout)
  - Figma: Each placed row has the timestamp text at a fixed x=10 (w~61) and the lyric text at a fixed x=81 — i.e. a fixed ~71pt timestamp column so all lyric text shares one left edge.
  - App: LyricsInspectorRow body (LyricsInspectorPane.swift:176-186) uses HStack(spacing: 6) with no fixed-width frame on the timestamp Text, so the lyric TextField left edge floats with the timestamp width and rows do not column-align.
  - Fix: Give the timestamp Text a fixed width (~71pt, .frame(width: 71, alignment: .leading)) so all lyric text aligns at a common left edge as in Figma.
- **[MEDIUM] Paste button (318:1503) — label & width** (text)
  - Figma: Footer button 318:1503 is 111pt wide, 28pt tall, right-aligned (x=237) with the short label 'Paste Lyrics…'.
  - App: LyricsInspectorPane.swift:148 uses Button("Paste Lyrics from Clipboard") with default sizing inside the VStack, so the label is the long form and the button is not constrained/right-aligned to 111pt.
  - Fix: Shorten the label to 'Paste Lyrics…' and right-align the button (HStack { Spacer(); Button(...) }) with a width near 111pt to match the Figma footer.
- **[MEDIUM] Queue/placed row vertical rhythm & inset** (spacing)
  - Figma: Rows are 29pt tall with ~2pt gaps (frames at y 0/31/62), text vertically inset 7pt; rows live in a content area inset 6pt from the pane edge (row frames start at x=6).
  - App: queueRow uses padding(.vertical, 7)+padding(.horizontal,10) and the VStacks use spacing:10 (LyricsInspectorPane.swift:111-112, :23); placed rows have zero padding when not current (LyricsInspectorRow.swift:187). Row height/gap and the 6pt content inset are not explicitly matched.
  - Fix: Normalize row height to ~29pt with ~2pt inter-row spacing and apply a consistent ~6pt horizontal content inset to both queue and placed rows so non-current rows align with current/cursor rows.
- **[LOW] Section dividers between zones** (extra)
  - Figma: Figma separates zones (offset / unplaced / placed) using section-header frames and vertical spacing only — there are no horizontal rule lines between the offset control and the queue, or between queue and placed.
  - App: LyricsInspectorPane.swift:21 and :25 insert Divider() after the offset control and between queueSection and placedSection.
  - Fix: Drop the Divider()s and rely on the section-header captions + spacing for separation, matching the cleaner Figma rhythm.
- **[LOW] Placed-row timestamp font** (font)
  - Figma: Timestamp text (e.g. 00:00:06.3 → app SMPTE) is monospaced; in Figma its glyph box is ~13pt tall implying ~11pt mono, distinct from the 13pt body lyric text.
  - App: LyricsInspectorRow.swift:178 uses .font(.caption.monospacedDigit()) (system caption ~11pt) rather than the DS mono token; acceptable size but not the DS.Text.monoSmall (11pt monospaced) token used elsewhere for timecodes.
  - Fix: Use DS.Text.monoSmall for the placed-row timestamp for token consistency with other timecode readouts.
- **[LOW] Header line-count badge position** (spacing)
  - Figma: Header frame 318:1470 is 37pt tall; '12 lines' badge right-aligned ending at x=346 (right inset 14), 'LYRICS' left at x=14.
  - App: header HStack (LyricsInspectorPane.swift:43-55) uses Spacer + pane padding(10) so the badge sits 10pt from the edge, not the Figma 14pt content inset; header height not pinned to 37pt.
  - Fix: Use a 14pt horizontal content inset (or align the pane padding to 14) so 'LYRICS' and the line-count badge match the Figma 14pt gutters.

## empty-state (DocumentEmptyState)

_The overall structure and copy match, but the Import button is the biggest miss — Figma shows a prominent filled cue/indigo accent button while the app renders a default plain SwiftUI button; the icon is undersized and rendered as a different glyph, and the help "?" button differs in styling, size, and inset._

- **[HIGH] Button "Import Media…" (I318:1354;35:9)** (color)
  - Figma: Filled accent button: fill cue/indigo #6155F5, white text (text-on-accent), radius 6 (sm), padding px12 py6, 13px semibold. It is the visual focal CTA.
  - App: Plain default SwiftUI Button("Import Media…") with no .buttonStyle / no tint / no background — DocumentEmptyState.swift:22-24. Renders as the system bordered/borderless button, not a filled indigo pill.
  - Fix: Give the button a filled accent style: .buttonStyle(.borderedProminent).tint(DS.Color cue/indigo #6155F5) or a custom style with .padding(.horizontal, DS.Space.md)/.padding(.vertical, 6), white label (DS text-on-accent), RoundedRectangle radius DS.Radius.sm (6). This is the one chroma element allowed by ADR-024 (cue-type color), so the indigo fill is intentional and must be reproduced.
- **[MEDIUM] Import glyph (ic-import / I318:1354;35:3)** (size)
  - Figma: Icon is 40×40pt.
  - App: Image(systemName: "square.and.arrow.down").font(.system(size: 30)) — DocumentEmptyState.swift:13-14. Glyph point size 30 (and an SF Symbol box renders smaller than its nominal size), so it reads noticeably smaller than the 40pt Figma icon.
  - Fix: Increase to roughly .font(.system(size: 40)) (or use a 40×40 frame) so the icon matches the Figma 40pt mark.
- **[MEDIUM] Help "?" button (I318:1354;35:13)** (other)
  - Figma: A 22×22 rounded button (radius 11 → circle) with panel fill #F4F2ED and a 1px border, containing a "?" glyph at 11px semibold text-secondary.
  - App: Plain Image(systemName: "questionmark.circle").font(.system(size: 14)), no background/fill, no border — DocumentEmptyState.swift:39-44. Renders as a bare SF Symbol question-mark-in-circle rather than a filled+bordered 22pt chip; glyph size 14 vs Figma container 22.
  - Fix: Wrap the glyph in a 22×22 circle with DS.Color.panel fill + 1px DS.Color.border stroke and a plain "?" Text at ~11pt semibold (or keep the symbol but size the container to 22 and add fill+border).
- **[LOW] Import glyph shape** (other)
  - Figma: Custom ic-import: a downward arrow into a tray/inbox tray outline (arrow pointing down into a horizontal base line, no surrounding box).
  - App: SF Symbol "square.and.arrow.down" (arrow up-and-out-of-a-box style outline) — DocumentEmptyState.swift:13. Different silhouette from the Figma import glyph (Figma is closer to arrow.down.to.line / tray.and.arrow.down).
  - Fix: Switch to an SF Symbol matching the Figma glyph, e.g. "arrow.down.to.line" or "tray.and.arrow.down", or use the exported ic-import asset.
- **[LOW] Help "?" button inset** (spacing)
  - Figma: Positioned at left 604.5 / top 10.5 within the 632-wide well, i.e. ~6pt inset from the inner content edge (top-right corner of the well, tucked into the padding).
  - App: .overlay(alignment: .topTrailing){ shortcutButton }.padding(DS.Space.md) → 12pt inset from the well's outer edge — DocumentEmptyState.swift:31, 45. Inset (12) differs from Figma's ~6-10pt and is measured against a different reference.
  - Fix: Reduce the button padding toward ~6pt (DS.Space.xs+) to sit closer to the well corner as in Figma.
- **[LOW] "No media imported" heading** (font)
  - Figma: 15px semibold, text-primary.
  - App: DS.Text.heading = Font.body.weight(.semibold) — DocumentEmptyState.swift:17. SF body is ~13pt, so the heading renders ~2pt smaller than the Figma 15px.
  - Fix: Acceptable if Dynamic Type is intended, but to match the 15px spec consider a 15pt semibold token; otherwise document the body-size choice.
- **[LOW] Inter vs SF Pro typeface** (font)
  - Figma: All text uses Inter (Semi Bold / Regular).
  - App: Uses SF Pro via DS.Text tokens — DocumentEmptyState.swift:17,20,27.
  - Fix: Intentional native-font substitution (Figma mock uses Inter as a stand-in for the system font). No change needed; noting for completeness.

## show-mode

_The Show Mode layout is structurally close — all three panes, the editor-mode switcher, full-bleed waveform, time ruler, cue markers, lyric chips, LTC strip, transport bar, and the framerate-bearing playhead clock all exist — but the read-only "lock" footer is entirely missing in the app, the waveform is over-dimmed vs the design, and a few header/spacing alignments drift from spec._

- **[HIGH] Inspector Footer · Read-only — Show Mode (318:1608 / 318:1610 lock / 318:1613 text)** (missing)
  - Figma: Persistent inspector footer, 360x33, with a lock glyph (11x12 at x=104.5) + 'Read-only — Show Mode' label, pinned to the bottom of the CueListPane (y=727, full 360 width).
  - App: CueListPane.swift:266-269 renders the footer only when NOT read-only (`if !isReadOnly { Divider(); CueListFooter() }`). In Show mode the footer is dropped entirely, and CueListFooter only ever shows a 'Manage Types…' button (CueListFooter.swift:11), never a read-only/lock indicator. No 'Read-only — Show Mode' string exists anywhere in the UI.
  - Fix: Add a dedicated read-only footer strip shown when isReadOnly: a bottom-pinned 33pt-tall row with an SF Symbol lock glyph + 'Read-only — Show Mode' in tertiary text, mirroring Figma 318:1608. Keep the Manage Types footer for the editable modes.
- **[MEDIUM] Waveform peaks dimming (Waveform 318:1530 / Vector 318:1531)** (color)
  - Figma: The waveform vector fills the well at the standard neutral peak grey at full strength; Show Mode does not visibly knock the peaks down — markers, playhead and peaks read at comparable contrast.
  - App: WaveformContainer.swift:145 applies `.opacity(editorMode == .show ? 0.45 : 1)`, dropping the peaks to 45%. This is well below what the design shows; the app reads as a heavily greyed-out waveform.
  - Fix: Raise the Show-mode peak opacity (e.g. ~0.7-0.8) so the locked state still reads but the waveform retains the contrast shown in the Figma, or confirm with the §9.1 audit whether 0.45 is intended and update the spec/screenshot to match.
- **[MEDIUM] Column Header leading swatch cell (318:1596, 8x8 at x=18)** (layout)
  - Figma: The inspector Column Header has an 8x8 swatch/marker frame at x=18 BEFORE the 'TIME' label (TIME starts at x=34), reserving a leading gutter that lines up with each row's color swatch.
  - App: headerRow (CueListPane.swift:220-250) starts directly with the 'Time' text column and has no leading swatch placeholder. Rows carry a ~14pt leading color swatch (noted in the comment at CueListPane.swift:23), so the header 'TIME' label is offset from the row time text — header and row columns do not share a leading gutter.
  - Fix: Add a fixed leading spacer/placeholder (~14-16pt) to headerRow matching the row swatch width so 'TIME/#/NAME/FADE' align with the row columns, as in Figma 318:1596.
- **[LOW] Column Header → first cue row gap (318:1595 vs 318:1601)** (spacing)
  - Figma: Column Header (y=102, h=20) ends at y=122; Cue List frame starts at y=122 with the first CueRowView inset 6pt (row at y=128 within Body). The header sits directly above the rows with only a thin separation, no extra padded block.
  - App: cueList (CueListPane.swift:260-271) stacks CueListSectionHeader (the 'CUES / 6 cues' block) THEN headerRow THEN a Divider then the List. headerRow adds `.padding(.vertical, DS.Space.sm)` (8pt top+bottom, CueListPane.swift:255), giving a taller header band than the 20pt Figma Column Header.
  - Fix: Trim headerRow vertical padding toward the 20pt Figma column-header height (e.g. reduce to ~4pt vertical) so the header band matches the design's compact 20pt strip.
- **[LOW] Inspector Header 'CUES' / 'n cues' (318:1592, 318:1593, 318:1594)** (spacing)
  - Figma: Inspector Header band is 37pt tall (y=65→102); 'CUES' micro-label at x=14 y=15, '6 cues' right-aligned at x=311 y=14. It is a distinct band separating the clock header from the column header.
  - App: Rendered via CueListSectionHeader(count:) inside cueList (CueListPane.swift:262). Confirm its height/padding matches 37pt and that the count label uses the same right-aligned 'n cues' treatment; the section header is stacked with spacing:0 so any internal padding mismatch shifts the whole column header down.
  - Fix: Verify CueListSectionHeader band height is ~37pt with 'CUES' at the left micro-label treatment and 'n cues' right-aligned, matching Figma 318:1592.
- **[LOW] EditorModeSwitcher / Switcher Bar (318:1526, 318:1527)** (size)
  - Figma: Switcher Bar is 62pt tall; EditorModeSwitcher control is 215x31 inset at x=16 y=15.5 (centered vertically in the 62pt bar), giving ~15.5pt top padding and 16pt leading.
  - App: PreviewPane.swift:23-24 puts EditorModeSwitcher as the first child of a VStack(spacing: DS.Space.sm = 8). There is no explicit 62pt switcher-bar container or 16pt horizontal inset around it at this level; the switcher's vertical placement is driven by the VStack spacing, not the Figma 15.5pt bar centering.
  - Fix: Confirm the switcher row reserves the 62pt bar height with ~16pt leading and 15.5pt top inset; if the surrounding VStack spacing yields a tighter top gap, wrap the switcher in a fixed-height bar to match Figma 318:1526.
- **[LOW] Waveform timeline height in video preview (Waveform Well 318:1529, h=602)** (size)
  - Figma: In Show Mode the Waveform Well fills the Preview Area at 602pt tall (648x602, the well minus title/transport), i.e. the waveform dominates the centre pane.
  - App: For audio items audioContent (PreviewPane.swift:118-120) lets the timeline fill (correct). But for VIDEO items videoContent pins the timeline strip to a fixed 100pt (PreviewPane.swift:108: `.frame(height: showTimelineBreakdown ? 160 : 100)`) below the video. The Show Mode design (an audio-led full-height waveform) is matched only on the audio path; the video path does not produce the full-height waveform the frame implies.
  - Fix: No change needed if Show Mode is audio-led by design; otherwise reconsider the fixed 100pt video timeline so the waveform can grow toward the 602pt well height when the centre pane is tall.

## video-project

_The center preview pane has the right top-to-bottom element order (switcher / video / waveform-with-cues / LTC / transport), but the video-vs-waveform proportion is wrong: Figma gives the video a fixed 452pt letterbox and the waveform a fixed ~150pt band joined by a 1pt divider inside one bordered "well," whereas the app pins the timeline to an absolute 100pt and lets the video flex, omits the divider, and renders no integrated letterbox card._

- **[HIGH] Preview Area / Waveform Well (318:1639) — video-to-waveform split** (layout)
  - Figma: Inside the 602pt-tall Waveform Well: Video Letterbox is 648×452 (top ~75%), a 1pt Divider sits at y=451, the Time Ruler is at y=456 (18pt), and the Waveform vector is at y=478 spanning 116pt — i.e. the waveform band below the divider is a fixed ~150pt (452→602), roughly a 75/25 video:waveform split.
  - App: videoContent stacks videoPlayer (flexible, takes all remaining height) above timeline pinned to an absolute height of 100pt (160 with breakdown) at PreviewPane.swift:108. The split is not proportional — as the window grows the video keeps growing while the waveform stays 100pt, so at the 760pt design height the waveform is ~100pt vs Figma's ~150pt and the video is much taller than 452pt.
  - Fix: Make the video letterbox a fixed/clamped height (~452pt at design size, or a ~74% proportion of the preview area) and give the waveform a proportional band (~25%, i.e. ~150pt at design size) rather than pinning it to 100pt. Consider GeometryReader-driven proportions instead of the absolute 100/160 frame at PreviewPane.swift:108.
- **[MEDIUM] Divider between video and waveform (318:1644)** (missing)
  - Figma: A 1pt rounded-rectangle Divider runs the full 648pt width at y=451, visually separating the video letterbox from the time ruler + waveform.
  - App: videoContent (PreviewPane.swift:104-109) is a VStack(spacing: 0) of videoPlayer directly above timeline with no separator rule between them.
  - Fix: Insert a 1pt DS divider (DS.Color hairline) between videoPlayer and timeline in videoContent.
- **[MEDIUM] Waveform Well container / Video Letterbox card (318:1640)** (layout)
  - Figma: The video + ruler + waveform are grouped in a single Waveform Well that is inset 16pt on each side (648 of 680) and is a rounded-rectangle 'Video Letterbox' card; the whole well is 602pt tall sitting inside a 614pt Preview Area (so ~6pt top/bottom breathing room, 62pt switcher bar above).
  - App: The preview is a single ZStack { DS.Color.surfaceSunken; content } with corner radius DS.Radius.sm and minHeight 180 (PreviewPane.swift:25-30); the video player and timeline are direct children with no 16pt horizontal inset card around the video and no explicit Waveform-Well grouping. Horizontal margins come from the outer .padding() in DocumentView, not a 16pt inset matching Figma's 648/680.
  - Fix: Verify the preview card's horizontal inset resolves to ~16pt within the 680pt center column and that the rounded card wraps video+ruler+waveform as one unit; align corner radius with the Figma letterbox (appears ~8-10pt, currently DS.Radius.sm = 6).
- **[MEDIUM] Cue lines / cue markers / playhead height (318:1675, 318:1690, 318:1693)** (size)
  - Figma: CueLines are 2pt wide × 116pt tall (full waveform height); CueMarker chips are 16×13 with the number above the waveform at y=472; Playhead is 1pt × 122pt (slightly taller than cues, extending up to the handle); Playhead Handle is a 12×8 vector triangle at the top; Playhead Time pill is 81×19 at y=473.
  - App: These are rendered inside WaveformContainer overlays (CueMarkersOverlay, PlayheadOverlay, WaveformPlayheadVisual) sized to the timeline band. Because the band is fixed at 100pt instead of the 116pt waveform + 18pt ruler region, cue lines/playhead are compressed below the Figma 116/122pt heights.
  - Fix: Once the waveform band is restored to ~150pt (ruler 18 + waveform 116 + chip headroom), the cue line (116pt) and playhead (122pt up to handle) heights will fall out naturally; verify they span the full waveform height and that the cue-number chip sits above the waveform top.
- **[LOW] Switcher Bar (318:1636 / EditorModeSwitcher 318:1637)** (spacing)
  - Figma: Dedicated Switcher Bar is 62pt tall; the EditorModeSwitcher (215×31) is inset x=16, y=15.5, leaving ~15.5pt above and below it.
  - App: EditorModeSwitcher is the first child of the body VStack(spacing: DS.Space.sm = 8) at PreviewPane.swift:23-24 with no explicit 62pt bar height or 15.5pt vertical centering; vertical rhythm is the 8pt VStack spacing plus the outer padding, not a 62pt band.
  - Fix: If matching Figma rhythm, give the switcher row ~62pt of vertical space (≈15.5pt padding top/bottom) rather than relying on the 8pt VStack spacing.
- **[LOW] Time Ruler (318:1646)** (layout)
  - Figma: An 18pt time ruler with minor ticks (1×4) every 32pt and major ticks (1×7) every 96pt labelled 00:00…03:00 sits BETWEEN the video divider (y=451) and the waveform (y=478), i.e. above the waveform.
  - App: The ruler is owned by WaveformContainer/WaveformRulerTicks inside the timeline area (PreviewPane.swift:160 WaveformContainer); it is not a sibling positioned between the video divider and waveform — it lives inside the flexible 100pt timeline band, so its vertical position and the 27pt gap (456→478→ruler-to-waveform) are not guaranteed to match.
  - Fix: Confirm the ruler renders directly under the divider with the waveform immediately below it inside the proportional band; the cramped 100pt band leaves little room for the 18pt ruler + 116pt waveform Figma allots.
- **[LOW] Empty / loading preview placeholder (318:1641 video image vs app placeholder)** (other)
  - Figma: When media is present the letterbox shows the actual video frame (Projection — Storm artwork). The frame is always the fixed 452pt letterbox.
  - App: videoPlayer is AVPlayerLayerView with videoGravity .resizeAspect inside a flexible frame; while waveform URL resolves, timeline shows placeholder("Loading…") (PreviewPane.swift:150). Empty-state uses a centered square.and.arrow.down largeTitle icon (PreviewPane.swift:218-235). These are app-only states not depicted in this Figma frame and are acceptable, but the resizeAspect video inside a flexible (non-452pt) frame will pillarbox/letterbox differently than the fixed Figma letterbox.
  - Fix: No change needed for the loading/empty states; ensure the video frame itself is clamped to the letterbox proportion so resizeAspect matches Figma's fixed 648×452 letterbox.
