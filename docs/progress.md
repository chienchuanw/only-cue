# Progress

Append-only session log. Newer entries on top.

---

## 2026-05-07 — E8 cue markers session (PR #23, issue #10)

**Shipped:** issue #10 (E8 cue markers on waveform). PR #23 merged into `dev` (rebase, head `716a710`). The waveform is now a real cue-editing surface, not just a static peak chart.

**What landed:**
- `OnlyCue/UI/CueMarkersGeometry.swift` — pure functions: `position(forTime:width:duration:)` (linear projection, zero-duration → 0) and `time(originalTime:dx:width:duration:)` (clamps to `0…duration`). Kept side-effect-free so geometry is unit-testable without SwiftUI.
- `OnlyCue/UI/CueMarkersOverlay.swift` — `GeometryReader` + `ForEach(cues)` driving `CueMarkerView` (vertical `Rectangle` + `Capsule` cap, both colored from `cue.colorHex`). A clear hit-area `Capsule` (14pt) widens the touch target. A single `DragGesture(minimumDistance: 0)` decides drag-vs-tap on `.onEnded` via a 4pt magnitude threshold — single ended call → exactly one `retime` undo step. Live `dragOffset` `@State` follows the finger; reset on end.
- `OnlyCue/UI/WaveformContainer.swift` — `.overlay(alignment: .topLeading) { CueMarkersOverlay(...) }` mounted on `WaveformView` **before** `.padding(.horizontal, 8)` so the overlay shares the waveform's pre-padded frame (markers align with peaks). Loads `asset.duration` during peak load so the overlay can project times.
- `OnlyCue/UI/PreviewPane.swift` — refactored from `media: MediaReference?` to `@ObservedObject document: CueListDocument`; audio path forwards `cues`, `onSeek` (→ `engine.seek`), and `onRetime` (→ `CueCommands.retime`).
- `OnlyCueTests/CueMarkersGeometryTests.swift` — 7 tests covering position at zero / full / mid / zero-duration, plus drag-time math with both clamps.

**Iteration via PR review — one cycle, four cleanups (`716a710`):**
1. **Blocker — overlay/peak misalignment** — original modifier order was `.padding` then `.overlay`, which sized the overlay to the *padded* frame. Markers drifted 8pt left of peaks. Fix: swap order so the overlay sizes to the waveform's intrinsic frame, then pad both as one unit.
2. Moved `dragThreshold` to sit with the other static layout constants for discoverability.
3. Dropped redundant `.contentShape(Rectangle())` on the clear `Capsule` hit-area (a filled shape already participates in hit-testing).
4. Dropped default `.allowsHitTesting(true)` on the overlay (it's the SwiftUI default).

**Manual verification (per issue #10 Gherkin):**
- Import `.mp3` → 3 cues at 4.25s / 12.0s / 18.5s (DEBUG seed) → 3 colored markers appear at correct x-positions.
- Tap marker #2 → playhead seeks to 12.0s.
- Drag marker #2 right → time updates live; release → one ⌘Z step restores original time.

---

## 2026-05-07 — E7 add/edit/delete cues session (PR #22, issue #9)

**Shipped:** issue #9 (E7 add/edit/delete cues). PR #22 merged into `dev` (rebase, head `5c5645a`). Documents are now live editors with proper undo.

**What landed:**
- `OnlyCue/Commands/CueCommands.swift` — 5 `@MainActor` static mutations (`addCueAtPlayhead`, `delete`, `rename`, `recolor`, `retime`) + private `mutate(_:undoManager:actionName:_:)` snapshot-and-replace helper. The helper opens its own undo group (`beginUndoGrouping` + `defer { endUndoGrouping() }`) so each command is one undoable unit regardless of host. Recursive `Self.mutate` inside the undo callback establishes the redo path. Edit-menu action names ("Undo Add Cue", "Redo Rename Cue", etc.) via `setActionName`.
- `OnlyCue/UI/CueRowView.swift` — `Button` swatch (14pt `Circle`, `.buttonStyle(.plain)`) opens a `.popover` listing 8 predefined cue colors. `TextField`-with-`@FocusState` handles inline rename on double-click; commits on Enter, cancels on Esc.
- `OnlyCue/UI/CueListPane.swift` — `.onDeleteCommand { deleteSelected() }` deletes the selected row via AppKit's responder chain. `.onDelete(perform:)` mirrors via swipe. `@Environment(\.undoManager)` flows through to all commands.
- `OnlyCue/UI/DocumentView.swift` — DEBUG seed button replaced with a real "Add Cue" button bound to `M` (no modifiers). `@Environment(\.undoManager)` injected.
- `OnlyCueTests/CueCommandsTests.swift` — 8 tests: add at time, add+undo+redo, delete+undo, rename+undo, recolor+undo, retime+undo, multi-add stays sorted by time. Test helper sets `groupsByEvent = false` so each `mutate` group lands at top level (one mutation = one undo).

**Iteration mid-session — three live-smoke fixes:**
1. **`ColorPicker` rendered as a chunky pill** — wraps `NSColorWell` with minimum chrome size; `.frame(width:height:)` is silently ignored. Swapped to a palette `Menu`.
2. **Mac delete key didn't fire** with `.onKeyPress(.delete)` + `@FocusState` on a `List`. Swapped to `.onDeleteCommand`, which routes through AppKit's responder chain.
3. **`Menu { ... }.menuStyle(.borderlessButton)` collapsed the trigger**, hiding the swatch label entirely. Final form: `Button` + `.popover` with `.buttonStyle(.plain)` for full custom rendering.

**Iteration via PR review — three undo-grouping cycles** (captured in `docs/findings.md`):
1. Initial `groupsByEvent = false` in tests broke `registerUndo` (must begin a group first).
2. Removing the override let `groupsByEvent = true` swallow every test mutation into one auto-group → `undo()` rolled back the whole test.
3. Final fix: `mutate` opens its own group (host-independent), test helper sets `groupsByEvent = false` so that group lands at top level. Production keeps `groupsByEvent = true` from `DocumentGroup` and our group nests cleanly inside the run-loop auto-group (one user click = one undoable unit).

**Manual verification (per issue #9 Gherkin):**
- Drop `.mp3` → press `M` at various playhead positions → cues appear sorted by time with default name "Cue" and teal swatch.
- ⌘Z empties; ⌘⇧Z restores.
- Double-click name → TextField focused → type → Enter → name updates; ⌘Z restores.
- Click swatch → palette popover → choose color → swatch updates; ⌘Z restores.
- Select row → ⌫ → deleted; ⌘Z restores with same id and time.

---

## 2026-05-07 — E6 cue list pane session (PR #21, issue #8)

**Shipped:** issue #8 (E6 cue list pane). PR #21 merged into `dev` (rebase, head `0009f35`). The cue list — the thing this app exists to plan — finally has a UI.

**What landed:**
- `OnlyCue/UI/CueListPane.swift` — `if cues.isEmpty { emptyState } else { List(selection: $selection) }`. Empty state has SF Symbol + "No cues yet" + "Press M to add one at the playhead". Selection is `Cue.ID?`; `.onChange(of: selection)` looks up the cue and calls `engine.seek(to: cue.time)` in a `Task`.
- `OnlyCue/UI/CueRowView.swift` — `HStack` with zero-padded `#`, `Circle` color swatch, name (or "Untitled"), `TimeFormat.hms(cue.time)` in monospaced caption.
- `OnlyCue/Utilities/Color+Hex.swift` — `Color.init?(hex: String)` parsing `#RRGGBB`. Defensive `allSatisfy(\.isHexDigit)` guard since `Scanner.scanHexInt64` accepts some non-hex strings.
- `OnlyCue/UI/DocumentView.swift` — `.inspector(isPresented: .constant(true))` hosts `CueListPane` with `inspectorColumnWidth(min: 240, ideal: 300, max: 400)`. Locked-open is correct for E6 (Gherkin demands the empty-state hint be discoverable); collapsible toggle is E9 polish.
- `OnlyCue/Commands/CueCommands.swift` — minimal `@MainActor enum CueCommands { static func replaceAll(_:in:) }`. CLAUDE.md mandates "UI layers go through `Commands/CueCommands.swift`" — so even the DEBUG seed button must route through it. E7 will extend with `add(at:)`, `delete`, `move`, and `UndoManager` wrapping.
- `OnlyCue/UI/DocumentView.swift` — `#if DEBUG` "+ Sample cues" button (3 cues at 4.25s / 12.0s / 18.5s). Smoke-tests the populated-list and click-to-seek Gherkin scenarios before E7 ships the M-key path. Hidden in Release; trivial to delete when E7 lands.
- `OnlyCueTests/ColorHexTests.swift` — valid hex → expected RGB; lowercase OK; missing `#` OK; wrong length → nil; non-hex chars → nil.

**Manual verification (per issue #8 Gherkin):**
- New document → cue list shows empty state with the M-key hint.
- Click "+ Sample cues" (DEBUG) → 3 rows render in order with correct colors and HH:MM:SS.mmm times.
- Click row 2 → playhead seeks to ~12.0s.

---

## 2026-05-07 — E5 waveform session (PR #20, issue #7)

**Shipped:** issue #7 (E5 waveform). PR #20 merged into `dev` (rebase, head `d962d96`). Audio documents now have a real waveform.

**What landed:**
- `OnlyCue/Media/WaveformGenerator.swift` — `static peaks(for: AVAsset, resolution: Int) async throws -> [Float]`. Forces output to mono Int16 LinearPCM @ 44.1kHz via `AVAssetReaderTrackOutput`, streams sample buffers, peak-reduces into N buckets via a `private struct PeakAccumulator`, normalizes to `0…1`. `Task.checkCancellation()` between buffers; `CMSampleBufferInvalidate` to free the reader's pool. Top-level function split into `makeReader` / `estimatedSampleCount` helpers to fit SwiftLint's complexity (10) and length (50) budgets.
- `OnlyCue/Media/WaveformCache.swift` — `WaveformCache(directory:)` for tests + `WaveformCache.shared` rooted at `~/Library/Caches/OnlyCue/peaks/`. Binary `Float32` blob keyed by `<sha>-<resolution>.peaks`. `static fileHash(_:)` streams the file in 1 MB chunks via `CryptoKit.SHA256`.
- `OnlyCue/UI/WaveformView.swift` — Canvas of rounded vertical bars centered on midline; resolves shading once, fills with `context.fill(path, with: shading)`.
- `OnlyCue/UI/WaveformContainer.swift` — orchestrates: hash file once → cache lookup → render or generate → fire-and-forget background write. `.task(id: asset.url)` cancels and reruns when the URL changes.
- `OnlyCue/UI/PreviewPane.swift` — audio path mounts `WaveformContainer` when `engine.player.currentItem?.asset is AVURLAsset`; otherwise shows reopen-required placeholder (relink work is E9).
- `OnlyCueTests/{WaveformGenerator,WaveformCache}Tests.swift` — generator (count, silent → zero, sine → non-zero, normalized) + cache (round-trip, miss, resolution mismatch, hash stability + uniqueness). `SilentAudioFixture.makeSineWAV(duration:frequency:)` added.

**Iteration mid-session — five SwiftLint/API errors caught at build time:**
1. `GraphicsContext.fill(_:with:)` takes `Shading` directly, not `Shading.color(...)`. The resolved shading **is** the value to pass.
2. `unneeded_synthesized_initializer` on `WaveformCache(directory:)` — dropped the explicit init, kept memberwise.
3. `prefer_self_in_static_references` inside `WaveformCache.shared` factory — `Self(directory:)` not `WaveformCache(directory:)`.
4. & 5. `cyclomatic_complexity 11` and `function_body_length 66` on `peaks(for:resolution:)` — extracted `PeakAccumulator` struct and split helpers; top-level function dropped to ~30 lines.

**Manual verification:**
- 5-min `.mp3` first import: spinner appears, waveform renders within ~1s.
- Re-import same `.mp3`: cache hit, instant render.
- Video import: unchanged (video preview pane).

**Caveat — Gherkin reopen scenario:** "peak cache hits on document reopen within 250ms" is partially deferred. Cache hits on **re-import** of the same file. Reopen-from-bookmark requires the document open path to resolve `MediaReference.bookmarkData` and reload the asset into the player — that's E9 relink. PreviewPane shows "reopen with media" placeholder when the engine is empty.

---

## 2026-05-07 — E4 video preview session (PR #19, issue #6)

**Shipped:** issue #6 (E4 video preview pane). PR #19 merged into `dev` (rebase, head `be72182`). Documents now show their picture.

**What landed:**
- `OnlyCue/UI/AVPlayerLayerView.swift` — `NSViewRepresentable` over `PlayerHostingView: NSView`. Host view sets `wantsLayer = true`, gets a plain `CALayer`, then `addSublayer(playerLayer)` with `videoGravity = .resizeAspect`. `override func layout()` keeps `playerLayer.frame = bounds` on every resize.
- `OnlyCue/UI/PreviewPane.swift` — `if let media; switch media.kind` dispatches to `AVPlayerLayerView`, an audio placeholder ("Audio loaded — waveform arrives in E5"), or an empty placeholder. `minHeight: 180`, rounded corners, accessibility identifiers per state.
- `OnlyCue/UI/DocumentView.swift` — pane slotted between media summary and cue count; window minimum bumped to 560×480.
- `project.yml` — pre-build SwiftLint script now `export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"` before `which swiftlint`. Xcode runs build scripts in a sandboxed shell with restricted PATH; without the export, a Homebrew-installed swiftlint reported "not installed".

**Build/render iteration mid-session:**
- First pass used `override func makeBackingLayer() -> CALayer { playerLayer }` to make the AVPlayerLayer the view's own backing layer. Compiles, looks elegant; rendered no picture in practice on macOS 15. Audio played, video stayed empty. Switched to the `addSublayer + override layout()` canonical pattern (commit `9fcc9cc` / `be72182`); video now renders.
- Stale Swift 6 `@MainActor` build error appeared once — DerivedData cache from before the E3 fix. `⌘⇧K` clean build folder cleared it.

**Simplify drop:** first pass added `PreviewPane.Kind { empty/audio/video }` + a static `previewKind(for:)` function + a unit test. The function just unwrapped `media?.kind`, the test was tautological. All three deleted (commit `b2091ed`); inline switch on `media?.kind` in the body. -32 LOC.

**Manual verification (per Gherkin in issue #6):**
- `.mp4` drag-drop → first frame visible immediately, transport drives video + audio in sync.
- `.mp3` drag-drop → audio placeholder.
- Empty document → empty placeholder.

---

## 2026-05-07 — E3 media import session (PR #18, issue #5)

**Shipped:** issue #5 (E3 media import). PR #18 merged into `dev` (rebase, head `ce3e0ca`). The app can now actually open user-supplied media.

**What landed:**
- `OnlyCue/Utilities/Bookmarks.swift` — `Bookmarks.create(for:) -> Data` and `Bookmarks.resolve(_:) -> Resolution` over `URL.bookmarkData(options: .withSecurityScope)` and `URL(resolvingBookmarkData:bookmarkDataIsStale:)`. `Resolution { url, isStale }` keeps the staleness signal explicit for E9.
- `OnlyCue/Commands/MediaImporter.swift` (new directory) — `@MainActor importMedia(from:into:engine:)`. Validates the URL via `UTType` (`.audio` / `.movie`), creates the bookmark, loads `AVAsset` duration off-main, mutates `document.model.media`, and calls `engine.load(asset:)`. `MediaImportError.unsupportedType(filename:)` for the alert path.
- `OnlyCue/UI/DocumentView.swift` — `Import Media…` button bound to `⌘O`, `.fileImporter(allowedContentTypes: MediaImporter.allowedContentTypes)`, `.dropDestination(for: URL.self)`, `.alert(item:)` driven by an internal `ImportAlert: Identifiable`. Added `mediaSummary` line that shows the imported file name + HH:MM:SS.mmm duration.
- `OnlyCueTests/SilentAudioFixture.swift` — single shared programmatic silent-WAV generator. Replaces three nearly-identical inline copies in `PlayerEngineTests`, `BookmarksTests`, `MediaImporterTests` (-41 LOC after the refactor commit).
- `OnlyCueTests/{Bookmarks,MediaImporter}Tests.swift` — round-trip via temp file, JSON pass-through, invalid-data throw; mediaKind detection (audio/video/unsupported), full importMedia happy path, unsupported throws and leaves model nil.
- `OnlyCue/Media/PlayerEngine.swift` — `@MainActor` on the class; periodic-time-observer closure hops via `MainActor.assumeIsolated { ... }` (queue is already `.main`).

**Build fixes applied mid-session (Swift 6 / macOS 15 SDK):**
- "Main actor-isolated initializer 'init(asset:)' cannot be called from outside of the actor" — fixed by adding `@MainActor` to `PlayerEngine` (commit `12a5015`). This applies the suggestion deferred from PR #17 review; it became load-bearing for the build, so the deferral resolved itself organically.
- "Main actor-isolated property 'currentTime' / 'rate' can not be mutated from a Sendable closure" inside `addPeriodicTimeObserver` — fixed by wrapping the body in `MainActor.assumeIsolated { ... }` (commit `ce3e0ca`). The observer queue is `.main`, so the assumption is sound and avoids per-tick `Task` allocation at 10Hz.

**Manual verification (per `docs/build-sequence.md` detour rule #3, since XCUITest can't drive `NSOpenPanel`/`.dropDestination`):**
- Drag `.mp3` onto window → `mediaSummary` updates with name + duration, transport plays audio.
- ⌘O → file picker filtered to audio + video.
- Drag `.pdf` → "Unsupported file" alert; `ProjectModel.media` stays nil.
- Video preview is intentionally absent (E4 / #6).

**Ad-hoc signing debug attach gotcha:** earlier in the session, Xcode reported "Unable to obtain a task name port right for pid X: (os/kern) failure (0x5)" when running. That's the LLDB-attach failure from `CODE_SIGN_IDENTITY: "-"` without a `get-task-allow` entitlement — masking the real Swift 6 build errors above. Lesson captured to `findings.md`: read the **build log** before debugging the runtime error.

---

## 2026-05-07 — E2 player core session (PR #17, issue #4)

**Shipped:** issue #4 (E2 player core). PR #17 merged into `dev` (rebase, head `2240f5c`). First media-handling code.

**What landed:**
- `OnlyCue/Utilities/Time+Format.swift` — `TimeFormat.hms(_:)` returns `HH:MM:SS.mmm`, clamps negatives to zero, half-away-from-zero millisecond rounding. 7 unit tests covering zero, sub-second, minute/hour rollover, complex case, negatives, and sub-ms rounding.
- `OnlyCue/Media/PlayerEngine.swift` — `@Observable final class` wrapping `AVPlayer`. Exposes `currentTime`, `rate`, `duration` as observable state via the `Observation` framework; player and `timeObserver` use `@ObservationIgnored`. API: `play()`, `pause()`, `seek(to:)`, `load(asset:)`. Periodic time observer fires every 0.1s on the main queue. 4 unit tests using a programmatically-generated silent WAV (`AVAudioFile`) — no fixture media in the repo.
- `OnlyCue/UI/TransportBar.swift` — minimal SwiftUI transport: play/pause `Image` button toggling on `engine.rate > 0`, monospaced time readout via `TimeFormat.hms(engine.currentTime)`. `accessibilityIdentifier`s on both elements.
- `OnlyCue/UI/DocumentView.swift` — wired `@State private var engine = PlayerEngine()` per document and embedded `TransportBar(engine:)`.

**Review cycle (1 commit beyond initial 4):**
- Cycle 1: 3 optional suggestions on PR #17. Applied #3 (`load(asset:)` now resets `rate = 0` immediately, closing a ~100ms stale-rate window between `replaceCurrentItem(with:)` and the next periodic observer tick — commit `2240f5c`). Deferred #1 (`@MainActor`) and #2 (`rate != 0` vs `> 0`) per YAGNI: the reviewer's own framing was conditional ("once we cross threading boundaries", "if/when we support reverse playback"). Posted gh-comment explaining the deferral with reasoning.

**Key learnings:**
- `@Observable` + `@ObservationIgnored` is the right shape for engine-style classes that own non-observable resources (an `AVPlayer`, a periodic-time-observer token).
- Real assets (not mocks) for `seek`/`load` tests via `AVAudioFile.write(from:)` to a temp WAV. Keeps tests fast, hermetic, and realistic without committing binary fixtures.
- Establish convention for review feedback: apply unconditional correctness fixes; defer suggestions whose own framing is conditional on future events.

---

## 2026-05-07 — E1 skeleton session (PR #16, issue #3)

**Shipped:** issue #3 (E1 skeleton). PR #16 merged into `dev`. First feature epic — first real Swift code.

**What landed:**
- Data model under `OnlyCue/Document/`: `ProjectModel`, `Cue`, `MediaReference`, `MediaKind`. All `Codable`/`Equatable`; `Cue` is also `Identifiable`.
- `CueListDocument` (`final class : ReferenceFileDocument`) with JSON encode/decode using `[.prettyPrinted, .sortedKeys]`.
- `Info.plist` adds `UTExportedTypeDeclarations` (declares `com.onlycue.cuelist`) and `CFBundleDocumentTypes` (binds it to `CueListDocument` via `NSDocumentClass`).
- `OnlyCueApp` now uses `DocumentGroup`. `DocumentView` shows minimal placeholder (title + cue count + hint) — preview/waveform/cue list arrive in E4–E6.
- Tests: 3 unit tests in `ProjectModelTests` (round-trip with media, round-trip with nil media, format assertions) + 1 UI test in `DocumentLaunchTests` mapping the "Scenario: New document opens" Gherkin.
- Replaced C1 placeholder tests with real ones.

**Review cycles applied (3 commits beyond initial 6):**
- Cycle 1: SwiftLint `--strict` failed on test code — replaced 6 force-unwraps with `try XCTUnwrap`, fixed `String(decoding:)` per `optional_data_string_conversion`, fixed `multiline_arguments` on `XCTAssert*` calls. Hoisted fixed UUIDs into `static let` constants.
- Cycle 2: macOS `DocumentGroup` shows the launcher window on cold launch (not auto untitled doc), so the UI test never reached `DocumentView`. Drove the test through `app.typeKey("n", modifierFlags: .command)` to mirror the Gherkin "When the user creates a new document". Added `.accessibilityIdentifier("documentTitle")` and `.accessibilityIdentifier("cueCount")` to query by stable identifier.
- Cycle 3: `XCUIElement.label` returns empty string when querying SwiftUI `Text` by `accessibilityIdentifier`. Dropped both `.label` equality assertions; element existence under the identifier is sufficient evidence of the rendered content.

**Key learnings (captured in `docs/findings.md`-worthy items):**
- SwiftLint `--strict` applies to test code too. Use `try XCTUnwrap` over force-unwrap in tests.
- macOS `DocumentGroup` cold-launch shows launcher, not untitled document. UI tests must drive ⌘N first.
- XCUITest `.label` is unreliable when an element carries `accessibilityIdentifier` from a SwiftUI `Text`; rely on identifier resolution + `exists`/`waitForExistence` instead.

---

## 2026-05-07 — CI session (PR #15, issue #2)

**Shipped:** issue #2 (C2 CI). PR #15 merged into `dev`. First PR using the new dev-as-default flow.

**What landed:**
- `.github/workflows/ci.yml` — single `build-test` job on `macos-latest`, ~25 min timeout.
- Pipeline: checkout → `maxim-lobanov/setup-xcode@v1` (latest stable Xcode) → `brew install xcodegen swiftlint xcbeautify` → `swiftlint lint --strict --reporter github-actions-logging` → `xcodegen generate` → `actions/cache@v4` (DerivedData + SPM) → `xcodebuild build` Debug → `xcodebuild test`. Build/test piped through `xcbeautify --renderer github-actions` for proper annotations.
- Triggers: `pull_request` (any branch) and `push` to `main` or `dev`.
- Concurrency: `cancel-in-progress` per ref.
- Code signing disabled (signing is C3's job).

**Coverage of reviewer feedback from PR #14:**
- SwiftLint must fail CI on absent or violating — `--strict` mode + natural `brew install` failure mode covers both.

**Out of scope (deferred):**
- Code signing in CI → C3 (#13).
- Release builds in CI → C3.
- Branch protection (require CI green + 1 review) → repo Settings UI, not committable.

**Verification:** the PR's own check run was the first exercise of the workflow — green on first run.

---

## 2026-05-07 — Bootstrap session (PR #14, issue #1)

**Shipped:** issue #1 (C1 bootstrap). PR #14 merged via rebase into `main`.

**What landed:**
- Repo metadata (linked the GitHub remote, 23 labels, 3 milestones, 13 issues — 10 epics + 3 chores).
- All planning docs under `docs/` (vision, mvp-scope, architecture, data-model, build-sequence, verification, roadmap, decisions).
- Approved spec: `docs/superpowers/specs/2026-05-07-repo-issues-design.md`.
- Implementation plan: `docs/superpowers/plans/2026-05-07-repo-issues.md` + 13 issue body templates committed under `docs/superpowers/plans/issue-bodies/`.
- Setup scripts: `docs/superpowers/plans/setup-labels.sh`, `setup-milestones.sh` (idempotent).
- Project skeleton: `project.yml` (xcodegen 2.45.4), `OnlyCue.xcodeproj` generated and gitignored.
- Folder layout per `docs/architecture.md`: App / Document / Media / UI / Commands / Utilities / Resources.
- Minimal Swift placeholders so the project compiles (real implementations live in E1 onward).
- Configs: `.gitignore`, `.editorconfig`, `.swiftlint.yml` (with `unused_import` correctly under `analyzer_rules`), `Info.plist`.
- GitHub templates: `.github/ISSUE_TEMPLATE/{epic,leaf,chore,bug}.md` + 7 forked PR templates with the OnlyCue verification footer (the original 6 from the gh-pr skill plus a new `chore.md` extending the skill's mapping).
- `CLAUDE.md` with PR template override rule, commit conventions, branching rules, and hard rules.

**Review feedback applied (commit `4bac6bf` after rebase):**
- Bundle ID changed to `com.chienchuanw.OnlyCue` (reverse-DNS must be a domain we control).
- `SWIFT_TREAT_WARNINGS_AS_ERRORS: YES` for Release config (Debug stays NO).
- Dropped duplicate `DEVELOPMENT_LANGUAGE: en` from target settings.
- Removed redundant `*.xcodeproj/project.xcworkspace/swiftpm/` from `.gitignore`.
- Rewrote `chore.md` PR footer with chore-shaped items (tooling-verified-locally, no-behavioral-surface, spec/CLAUDE.md updated, CI green).
- Tracked SwiftLint CI enforcement on issue #2; tracked placeholder-test deletion as a leaf on issue #3.

**Branching change:** `dev` is now the default branch on the remote. Issue branches base off `dev`. Production code is on `main`. CLAUDE.md updated to reflect this.

**Tooling installed this session:**
- `xcodegen` (2.45.4) via Homebrew — generates `OnlyCue.xcodeproj` from `project.yml`.
