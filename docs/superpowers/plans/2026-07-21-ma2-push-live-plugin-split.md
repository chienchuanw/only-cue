# grandMA2 live/plugin sheet split — Implementation Plan (#688)

> UI refactor — the logic layer (`commandOutcome`/`pluginOutcome`) is unchanged and already unit-tested, so verification is: app builds, full unit suite green, `swiftlint --strict` clean. No new pure logic to TDD.

**Goal:** Trim the Send-to-grandMA2 (live) sheet to the fields Approach A actually uses, and give Export-grandMA2-plugin (C) its own config sheet.

## Global Constraints

- Swift 6, macOS ≥ 14; `swiftlint --strict` clean; Conventional Commits, no `Co-Authored-By`.
- No direct `ProjectModel` mutation (persist via `CueCommands.setMA2PushTarget`).
- Regenerate the project (`xcodegen generate`) after adding files. Filter test noise with `2>&1 | grep -v "Connection\]"`.

---

### Task 1: Trim `MA2PushSheet` (A)

**File:** `OnlyCue/UI/MA2PushSheet.swift`

- [ ] Rewrite `targetCard`'s `Grid` to drop the **Timecode slot** field and the **TC command** `Picker`, leaving: Sequence name (already above the grid), Sequence slot, Executor (page.exec). Keep the `@State timecodeSlot` / `timecodeCommand` and their inclusion in `currentTarget` (seeded from the saved target) so C's persisted values are preserved.
- [ ] `xcodegen generate` → build → full `OnlyCueTests` → `swiftlint --strict`. All green (the push path never used those fields, so existing tests are unaffected).
- [ ] Commit: `feat(ma2): trim send-to-grandMA2 sheet to live-push fields`

### Task 2: `MA2PluginExportSheet` (C) + presenter rewire

**Files:** create `OnlyCue/UI/MA2PluginExportSheet.swift`; modify `OnlyCue/UI/MA2PluginExportPresenter.swift`

- [ ] Create `MA2PluginExportSheet` (model on `MA2PushSheet`/`MA2PushSheetPresenter`): `init(item:cuePointTypes:framerate:onSaveTarget:onDismiss:)`; `@State` for sequence name / sequence slot / executor page+number / timecode slot / TC command / includedTypeIDs, seeded from `item.ma2PushTarget ?? default`; a target card with the **full** field set (incl. timecode slot + Go/Goto), a types filter card, a pre-flight card, and an **Export…** button. Export → `MA2PushRequestBuilder.pluginOutcome(item:target:framerate:datetime:)`: on `.blocked` set the pre-flight issues; on `.ready(bundle)` call `onSaveTarget(target)` then present `NSSavePanel` and `MA2PluginWriter.write(bundle, toDirectory:)`, surfacing a write error alert. Accessibility ids `ma2PluginExport*`.
- [ ] Rewire `MA2PluginExportPresenter` to `@State private var presentedItem: MediaItem?`, set it on `.exportMA2PluginRequested` (object = `MediaItem.ID`, nil = active), and present `MA2PluginExportSheet` via `.sheet(item:)` (mirror `MA2PushSheetPresenter`). Move the old inline `pluginOutcome`/`save`/alert logic into the sheet.
- [ ] `xcodegen generate` → build → full suite → `swiftlint --strict`. All green.
- [ ] Commit: `feat(ma2): add config sheet to the grandMA2 plugin export`

## Self-Review

- Spec coverage: trim live sheet → Task 1; plugin config sheet + presenter → Task 2. Both sheets persist the same target via `setMA2PushTarget`.
- No new logic → no new unit tests; existing suite + build + lint are the gate (per the project's MA2-flow convention).
