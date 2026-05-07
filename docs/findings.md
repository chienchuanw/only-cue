# Findings

Non-obvious things learned during development. Things you'd want to remember next time you hit the same situation.

---

## `UndoManager` grouping in tests vs production — both halves required

In production with `DocumentGroup`'s injected `UndoManager`, `groupsByEvent = true` opens a fresh group at the start of each run-loop iteration. Each user click runs in one iteration, so one click = one auto-group = one ⌘Z step. Works out of the box.

In **synchronous test code**, that auto-group never closes (no run-loop turn), so every `registerUndo` call from a sequence of `add → delete → rename` lands in the **same** group. A single `undo.undo()` rolls back **everything**.

The fix is to do both:

1. Production-side, have the command layer open its own group:

   ```swift
   private static func mutate(...) {
       undoManager?.beginUndoGrouping()
       defer { undoManager?.endUndoGrouping() }
       // mutate, registerUndo, setActionName...
   }
   ```

2. Test-side, disable the auto-group so the command's group is the top-level group:

   ```swift
   private func makeUndoManager() -> UndoManager {
       let undo = UndoManager()
       undo.groupsByEvent = false
       return undo
   }
   ```

In production, `mutate`'s explicit group nests inside the run-loop auto-group — but since each user event runs in its own turn, the auto-group ends up containing exactly one inner group. One undoable unit per user click. ✓

Failure modes by combination:
| `groupsByEvent` | in-`mutate` grouping | symptom |
|---|---|---|
| `true` | none | all sync mutations share one auto-group; `undo()` rolls back all |
| `false` | none | `registerUndo` throws "must begin a group" |
| `true` | yes | nested group inside auto-group; `undo()` rolls back the outer auto-group → still all |
| `false` | yes | `mutate`'s group is top-level; `undo()` rolls back exactly that command ✓ |

Took three PR review cycles on PR #22 to converge on this. Don't repeat.

## SwiftUI macOS gotchas around inline list-row controls

Three things that bit us building the cue row's swatch + delete affordances (E7):

1. **`ColorPicker` cannot be sized small.** Wraps `NSColorWell`, which has minimum chrome dimensions. `.frame(width: 16, height: 16)` is silently ignored — the well renders at ~80×24pt and overflows compact rows. Don't put a bare `ColorPicker` in a `List` row. Replace with a palette `Button` + `.popover`.

2. **`Menu { ... } label: { Circle() }.menuStyle(.borderlessButton)` collapses the label.** The borderless style hides the trigger view entirely on macOS 14 — the Circle disappears, the menu becomes invisible. Without the borderless style, Menu uses its default popup-button chrome (which is the same chunky pill as `ColorPicker`). No middle ground that works for tiny inline labels.

   Working pattern: `Button + .popover` with `.buttonStyle(.plain)` for full custom rendering, no system-style fighting.

   ```swift
   Button { showPopover.toggle() } label: { Circle().fill(color).frame(width: 14, height: 14) }
       .buttonStyle(.plain)
       .popover(isPresented: $showPopover) { paletteList }
   ```

3. **`.onKeyPress(.delete)` on SwiftUI `List` + `@FocusState` doesn't reliably capture the Mac delete (backspace) key.** The canonical macOS path is `.onDeleteCommand`, which routes through AppKit's `deleteBackward:` responder action that `List` participates in via selection. No focus-state machinery needed.

---

## SwiftUI `GraphicsContext.fill(_:with:)` takes `Shading` directly

A common mistake when using `Canvas`:

```swift
// Wrong — `color` is a static factory on Shading, not an instance member
let resolved = context.resolve(.color(.accentColor))
context.fill(path, with: .color(resolved.color))   // compile error

// Right — pass the resolved shading itself
let shading = context.resolve(.color(.accentColor))
context.fill(path, with: shading)
```

`context.resolve(_:)` returns a `GraphicsContext.Shading` that has been pre-evaluated against the canvas's color scheme / environment. You hand that resolved shading to `fill` / `stroke` directly. There is no `.color` instance property to extract.

## SwiftLint default budgets: 10 cyclomatic complexity, 50-line function body

Both rules are on by default and bite as soon as a function gathers a few branches plus a non-trivial buffer-processing loop. `WaveformGenerator.peaks(for:resolution:)` tripped both at 11/66 — the fix is structural, not config:

- Extract per-iteration state into a `private struct PeakAccumulator` with `mutating func ingest(...)` + `mutating func finalize() -> [Float]`.
- Pull setup into helpers: `makeReader(asset:track:)`, `estimatedSampleCount(asset:resolution:)`.
- Top-level function becomes a thin orchestrator (~30 lines) over the helpers and accumulator.

This shape also reads better under review than one long imperative function.

## `unneeded_synthesized_initializer` and `prefer_self_in_static_references` (SwiftLint)

Two opt-in rules on by default in this project:

- `unneeded_synthesized_initializer`: don't write an explicit memberwise init for a struct whose properties already match what the synthesized init would produce. `struct Foo { let x: Int }` is enough.
- `prefer_self_in_static_references`: inside a type's own static methods/lazy initializers, refer to the surrounding type as `Self`, not the literal type name. `WaveformCache.shared`'s factory closure must use `Self(directory:)`.

---

## `AVPlayerLayer` in `NSViewRepresentable`: use addSublayer, not `makeBackingLayer`

The "elegant" pattern for hosting `AVPlayerLayer` in an `NSView` is to override `makeBackingLayer()` to return the `AVPlayerLayer` directly, so the player layer **is** the view's backing layer. It compiles, AppKit accepts it, and audio plays — but on macOS 15 the layer rendered no video frames in practice. Use the canonical addSublayer pattern instead:

```swift
final class PlayerHostingView: NSView {
    let playerLayer = AVPlayerLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        playerLayer.videoGravity = .resizeAspect
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }
}
```

Plain `CALayer` as the backing layer; `AVPlayerLayer` as a sublayer; `override func layout()` keeps the sublayer's frame in sync with `bounds` across window resizes. `videoGravity = .resizeAspect` for aspect-fit.

## Xcode pre-build scripts run with a stripped PATH

A pre-build "Run Script" in Xcode (or `preBuildScripts:` in `project.yml`) executes in a sandboxed shell that does **not** inherit your interactive PATH. Homebrew-installed tools at `/opt/homebrew/bin` (Apple Silicon) or `/usr/local/bin` (Intel) are missing, so `which swiftlint` reports "not installed" even when `brew install swiftlint` succeeded. Always prepend the Homebrew paths at the top of the script:

```yaml
preBuildScripts:
  - name: SwiftLint
    script: |
      export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
      if which swiftlint > /dev/null; then
        swiftlint
      else
        echo "warning: SwiftLint not installed (brew install swiftlint)"
      fi
```

Same applies to swiftgen, sourcery, xcodegen invoked from a script, etc.

---

## macOS 15 SDK + Swift 6 isolates `AVPlayerItem.init(asset:)` to MainActor

Building against the macOS 15 SDK with Swift 6 strict concurrency surfaces:

> `Main actor-isolated initializer 'init(asset:)' cannot be called from outside of the actor; this is an error in the Swift 6 language mode`

Anything that constructs `AVPlayerItem` inside a non-`@MainActor` method fails. The fix is to mark the wrapper class `@MainActor` so its methods inherit the isolation. For `PlayerEngine`, that also means the periodic-time-observer closure (which is `@Sendable`) loses the type-system guarantee that it runs on `.main` even when you pass `.main` as the queue. Wrap the closure body in `MainActor.assumeIsolated { ... }` — synchronous, no per-tick `Task` allocation, and the assumption is sound because we passed `queue: .main` ourselves.

```swift
@Observable
@MainActor
final class PlayerEngine { ... }

timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
    MainActor.assumeIsolated {
        guard let self else { return }
        self.currentTime = CMTimeGetSeconds(time)
        self.rate = self.player.rate
    }
}
```

When the wrapper class becomes `@MainActor`, sync-call test methods (`engine.play()`) need `@MainActor` on the test class to inherit isolation.

## Ad-hoc signing + missing `get-task-allow` blocks Xcode debug attach (and masks real build errors)

`CODE_SIGN_IDENTITY: "-"` (ad-hoc) without an entitlements file containing `com.apple.security.get-task-allow = YES` makes Xcode fail to attach LLDB on macOS 14+:

> `Unable to obtain a task name port right for pid X: (os/kern) failure (0x5)`

This error is shown in the run console even when there is also a **build** error preventing the app from being produced — the run-attach failure is what surfaces visually. Lesson: when this error appears, switch to the **Issue navigator** / build log first. Don't troubleshoot the signing-debug error until you've confirmed the build is clean.

Workarounds for actual debugging once the build is green: Product → Run Without Debugging (⌘⌃R), or open the built `.app` from Finder. Proper fix (deferred — chore-shaped infra change): add `Debug.entitlements` with `get-task-allow = YES` and reference it via `CODE_SIGN_ENTITLEMENTS` in `project.yml` for the Debug config only.

## XCUITest can't drive `NSOpenPanel` or SwiftUI `.dropDestination`

For E3 media import, the natural acceptance tests are "user picks file via ⌘O" and "user drops file on window". Both are out of XCUITest's reach: `NSOpenPanel` runs out-of-process (sandboxed `com.apple.appkit.xpc.openAndSavePanelService`) so the test app can't see its UI tree, and SwiftUI's `.dropDestination` listens for AppKit drag events that XCUITest can't synthesize. Recourse: cover the contract with unit tests on the import command, and rely on manual verification per `docs/build-sequence.md` detour rule #3.



## xcodegen `info:` directive overwrites custom Info.plist

The `targets.<name>.info: { path: ... }` key in `project.yml` causes xcodegen to **generate** an `Info.plist` at the given path — overwriting any custom contents (including `UTExportedTypeDeclarations`).

**Workaround:** don't use the `info:` key. Instead set in target settings:
```yaml
GENERATE_INFOPLIST_FILE: NO
INFOPLIST_FILE: OnlyCue/Resources/Info.plist
```

Then xcodegen leaves the plist alone.

## Reverse-DNS bundle IDs must use a domain you control

Started with `com.onlycue.OnlyCue`; `onlycue.com` isn't owned. Changed to `com.chienchuanw.OnlyCue` before any persistence layer (UserDefaults, Keychain, document UTType) was wired up. Renaming a bundle ID later requires migration code for every persistence layer that uses it as a namespace.

## SwiftLint `unused_import` belongs under `analyzer_rules`, not `opt_in_rules`

It's an analyzer rule — runs only with `swiftlint analyze`, not regular lint. SwiftLint emits a config warning if it's listed under `opt_in_rules`. Move it to its own `analyzer_rules` block.

## SwiftLint can't load SourceKit on Command Line Tools-only systems

`Loading sourcekitdInProc.framework/Versions/A/sourcekitdInProc failed` when running `swiftlint` from a system that has only Xcode Command Line Tools, not full Xcode. The lint engine still produces results (exit 0 was observed) but analyzer rules silently fail. Inside Xcode the framework is available, so the pre-build script works there. CI must be on a runner with full Xcode.

## gh-pr skill has no `chore` PR type by default

The skill's PR types are `feat / bug / refactor / doc / perf / security`. Repos that use `chore` as a kind label need to add `.github/PULL_REQUEST_TEMPLATE/chore.md` and document the mapping in `CLAUDE.md`. Without that, the gh-pr skill falls back to inferring from commit history or asks the user.

## gh-pr skill template fork requires CLAUDE.md override rule

The skill reads PR templates from a hardcoded path inside its own bundle (`<skill-path>/templates/{type}.md`). To fork the templates into the repo (so the OnlyCue verification footer is enforced), put forked copies under `.github/PULL_REQUEST_TEMPLATE/{type}.md` and add an explicit override rule in `CLAUDE.md` redirecting the skill to read from the repo. Without the rule, the skill silently uses its bundled templates.

## Idempotent gh setup scripts beat one-shot snippets

`gh label create --force` updates existing labels in place. For milestones, the upstream API has no `--force`, so wrap in a script that checks existence by title first. Both flow through `setup-labels.sh` and `setup-milestones.sh` so re-running them is safe and the team can rebuild repo state from text.

## xcodegen `configs:` block lets you split warning-as-error per config

```yaml
configs:
  Debug: debug
  Release: release

settings:
  configs:
    Debug:
      SWIFT_TREAT_WARNINGS_AS_ERRORS: NO
    Release:
      SWIFT_TREAT_WARNINGS_AS_ERRORS: YES
```

Debug stays loose for fast iteration; Release fails fast on drift. The `configs:` keys at the project root tell xcodegen which Xcode build configurations to generate.

## SwiftLint `--strict` lints test code too

The `.swiftlint.yml` `included:` list covers `OnlyCueTests/` and `OnlyCueUITests/`, so test code is held to the same opt-in rules as production (`force_unwrapping`, `multiline_arguments`, `optional_data_string_conversion`, etc.). In tests:

- Replace `something!` with `try XCTUnwrap(something)` — test methods must `throws`. Failures point at the exact line instead of crashing the test harness.
- `String(decoding: data, as: UTF8.self)` triggers `optional_data_string_conversion`. Use `try XCTUnwrap(String(bytes: data, encoding: .utf8))` instead.
- `XCTAssertTrue(a, "msg")` on one line triggers `multiline_arguments` once you cross the line-length threshold. Either keep both args on one short line or put each on its own line.

## macOS `DocumentGroup` cold launch shows the launcher window, not an untitled doc

Unlike iOS, on macOS a `DocumentGroup`-based app shows the system **launcher / start window** on cold launch (newer macOS) or the open-file panel (older). It does **not** auto-create an untitled document. Implications for UI tests:

- After `app.launch()`, send `app.typeKey("n", modifierFlags: .command)` (or click the "New Document" button) to reach a document window before asserting on document content.
- Auto-opening untitled docs via `applicationShouldOpenUntitledFile` is a UX commitment — Pages/Numbers/Keynote don't do it. Keep that decision out of E1; revisit in E9 polish if desired.

## XCUITest `.label` is unreliable when querying SwiftUI `Text` by `accessibilityIdentifier`

If you `.accessibilityIdentifier("foo")` a SwiftUI `Text("Bar")` and then query `app.staticTexts["foo"]`, the element resolves correctly via `waitForExistence` / `exists`, but `.label` often comes back as `""` (sometimes the value surfaces via `.value` in AppKit-bridged paths, sometimes not at all). Don't assert on `.label` for identifier-resolved elements — rely on existence under the identifier as proof of rendering. If you genuinely need to assert visible copy, use a SwiftUI snapshot or unit test on the view body, not XCUITest.

## A `Closes #N` line in the PR body auto-closes the issue at merge

Verified on PR #14 → issue #1. No need to manually close the issue. Same syntax works for `Fixes #N` / `Resolves #N`. If the PR uses GitHub's "linked issues" UI, that's separate from this body marker but functions identically.
