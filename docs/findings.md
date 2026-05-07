# Findings

Non-obvious things learned during development. Things you'd want to remember next time you hit the same situation.

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
