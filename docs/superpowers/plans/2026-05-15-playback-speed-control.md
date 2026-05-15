# Playback Speed Control Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user adjust media playback speed in [0.1×, 3.0×] in 0.1× steps via keyboard shortcuts and a new `Playback` menu — a rehearsal aid that does not mutate the timeline or persist to `.cuelist`.

**Architecture:** All rate state lives in `PlayerEngine`. Audio pitch is preserved (`audioTimePitchAlgorithm = .spectral`). A new `Playback` `CommandMenu` posts `NotificationCenter` actions that `DocumentView` forwards to the engine — matching the existing pattern used by every other menu-driven action. A new transport-bar badge shows the current rate (hidden at 1.0×, flashes ~1.2s on change). LTC output and rate ≠ 1.0× are mutually exclusive, enforced at every rate-change entry point and at LTC-enable.

**Tech Stack:** Swift 6, SwiftUI, AVFoundation (`AVPlayer.rate`, `AVPlayerItem.audioTimePitchAlgorithm`), the existing `KeymapAction` / `KeymapStore` / `AppCommands` / `LTCRoutingStore` machinery.

**Spec:** [`docs/superpowers/specs/2026-05-15-playback-speed-control-design.md`](../specs/2026-05-15-playback-speed-control-design.md)

---

## File Structure

**Modify:**
- `OnlyCue/Media/PlayerEngine.swift` — add `playbackRate` state + `setPlaybackRate(_:)` / `nudgePlaybackRate(by:)` / `resetPlaybackRate()` / `applyAudioTimePitchAlgorithm()`; thread `playbackRate` through `play()` and `load(asset:)`.
- `OnlyCue/App/KeymapAction.swift` — three new cases + display names.
- `OnlyCue/App/Keymap.swift` — default bindings for the three new cases.
- `OnlyCue/App/AppCommands.swift` — new `CommandMenu("Playback")`.
- `OnlyCue/UI/DocumentView.swift` — three notification observers + LTC-enable side-effect (reset rate to 1.0×).
- `OnlyCue/UI/TransportBar.swift` — embed the new `PlaybackRateBadge`.
- `OnlyCue/LTC/LTCRoutingStore.swift` — emit a notification on enable (so the engine can hear it) **only if** the existing API doesn't already publish a usable signal; verify first.

**Create:**
- `OnlyCue/UI/PlaybackRateBadge.swift` — the small badge + popover view.
- `OnlyCueTests/PlayerEnginePlaybackRateTests.swift` — unit tests for the new engine API.
- `OnlyCueUITests/PlaybackSpeedUITests.swift` — UI smoke for menu items + badge.

---

## Task 1: Add `playbackRate` state and pitch algorithm to PlayerEngine

**Files:**
- Modify: `OnlyCue/Media/PlayerEngine.swift`
- Test: `OnlyCueTests/PlayerEnginePlaybackRateTests.swift` (new)

- [ ] **Step 1: Write the failing tests**

Create `OnlyCueTests/PlayerEnginePlaybackRateTests.swift`:

```swift
import AVFoundation
import XCTest
@testable import OnlyCue

@MainActor
final class PlayerEnginePlaybackRateTests: XCTestCase {

    func test_defaultPlaybackRate_isOnePointZero() {
        let engine = PlayerEngine()
        XCTAssertEqual(engine.playbackRate, 1.0, accuracy: 0.0001)
    }

    func test_setPlaybackRate_clampsAndSnaps() {
        let engine = PlayerEngine()

        engine.setPlaybackRate(-1.0)
        XCTAssertEqual(engine.playbackRate, 0.1, accuracy: 0.0001)

        engine.setPlaybackRate(0.0)
        XCTAssertEqual(engine.playbackRate, 0.1, accuracy: 0.0001)

        engine.setPlaybackRate(0.04)
        XCTAssertEqual(engine.playbackRate, 0.1, accuracy: 0.0001)

        engine.setPlaybackRate(0.14)
        XCTAssertEqual(engine.playbackRate, 0.1, accuracy: 0.0001)

        engine.setPlaybackRate(0.15)
        XCTAssertEqual(engine.playbackRate, 0.2, accuracy: 0.0001)

        engine.setPlaybackRate(2.46)
        XCTAssertEqual(engine.playbackRate, 2.5, accuracy: 0.0001)

        engine.setPlaybackRate(3.05)
        XCTAssertEqual(engine.playbackRate, 3.0, accuracy: 0.0001)

        engine.setPlaybackRate(99.0)
        XCTAssertEqual(engine.playbackRate, 3.0, accuracy: 0.0001)
    }

    func test_nudgePlaybackRate_up_stopsAtThree() {
        let engine = PlayerEngine()
        // 1.0 + 20 * 0.1 → 3.0 exactly
        for _ in 0..<25 {
            engine.nudgePlaybackRate(by: 0.1)
        }
        XCTAssertEqual(engine.playbackRate, 3.0, accuracy: 0.0001)
    }

    func test_nudgePlaybackRate_down_stopsAtOneTenth() {
        let engine = PlayerEngine()
        for _ in 0..<25 {
            engine.nudgePlaybackRate(by: -0.1)
        }
        XCTAssertEqual(engine.playbackRate, 0.1, accuracy: 0.0001)
    }

    func test_resetPlaybackRate_returnsToOne() {
        let engine = PlayerEngine()
        engine.setPlaybackRate(0.5)
        engine.resetPlaybackRate()
        XCTAssertEqual(engine.playbackRate, 1.0, accuracy: 0.0001)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run from the OnlyCue project root:

```bash
xcodebuild test \
  -project OnlyCue.xcodeproj \
  -scheme OnlyCue \
  -destination 'platform=macOS' \
  -only-testing:OnlyCueTests/PlayerEnginePlaybackRateTests \
  2>&1 | tail -40
```

(Regenerate the project first with `xcodegen generate` if `OnlyCue.xcodeproj/` is missing.)

Expected: build failure ("value of type 'PlayerEngine' has no member 'playbackRate' / 'setPlaybackRate' / 'nudgePlaybackRate' / 'resetPlaybackRate'").

- [ ] **Step 3: Add the public surface to `PlayerEngine`**

In `OnlyCue/Media/PlayerEngine.swift`, add a new stored property below `private(set) var duration: TimeInterval = 0` (around line 15):

```swift
    /// User-facing playback rate. Range `[0.1, 3.0]`, snapped to 0.1.
    /// Distinct from `rate`, which reflects `AVPlayer.rate` (0 when paused).
    /// `playbackRate` is the rate `play()` will apply to the player.
    private(set) var playbackRate: Float = 1.0
```

Then add this method group near the bottom of the class, just above `private func observeTime()` (around line 91):

```swift
    // MARK: - Playback rate

    /// Allowed playback rate range, inclusive.
    static let playbackRateRange: ClosedRange<Float> = 0.1...3.0
    /// Snap step for `setPlaybackRate(_:)`.
    static let playbackRateStep: Float = 0.1

    /// Set the playback rate, clamped to `playbackRateRange` and snapped to
    /// the nearest `playbackRateStep`. If the player is currently playing,
    /// the live `AVPlayer.rate` is updated to match.
    ///
    /// LTC interlock is enforced by callers (the keymap action + menu item);
    /// this method itself does not consult LTC state so unit tests can drive
    /// the rate without standing up a routing store.
    func setPlaybackRate(_ rate: Float) {
        let clamped = min(max(rate, Self.playbackRateRange.lowerBound), Self.playbackRateRange.upperBound)
        let snapped = (clamped / Self.playbackRateStep).rounded() * Self.playbackRateStep
        // Float rounding noise → re-clamp.
        playbackRate = min(max(snapped, Self.playbackRateRange.lowerBound), Self.playbackRateRange.upperBound)
        if player.rate > 0 {
            player.rate = playbackRate
        }
    }

    /// Increment / decrement by `delta` (typically ±0.1). Clamps via `setPlaybackRate(_:)`.
    func nudgePlaybackRate(by delta: Float) {
        setPlaybackRate(playbackRate + delta)
    }

    /// Reset to 1.0×.
    func resetPlaybackRate() {
        setPlaybackRate(1.0)
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
xcodebuild test \
  -project OnlyCue.xcodeproj \
  -scheme OnlyCue \
  -destination 'platform=macOS' \
  -only-testing:OnlyCueTests/PlayerEnginePlaybackRateTests \
  2>&1 | tail -20
```

Expected: 5 tests passed.

- [ ] **Step 5: Commit**

```bash
git add OnlyCue/Media/PlayerEngine.swift OnlyCueTests/PlayerEnginePlaybackRateTests.swift
git commit -m "feat(media): add playback rate state to PlayerEngine"
```

---

## Task 2: Apply playback rate on play(), preserve pitch on load

**Files:**
- Modify: `OnlyCue/Media/PlayerEngine.swift`
- Test: `OnlyCueTests/PlayerEnginePlaybackRateTests.swift`

- [ ] **Step 1: Add the failing test**

Append to `PlayerEnginePlaybackRateTests`:

```swift
    func test_play_appliesCustomPlaybackRate() async throws {
        let engine = PlayerEngine()
        let url = try silentAssetURL(seconds: 1.0)
        await engine.load(asset: AVURLAsset(url: url))
        engine.setPlaybackRate(0.5)
        engine.play()
        // AVPlayer needs a beat to commit the rate.
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(engine.player.rate, 0.5, accuracy: 0.01)
        engine.pause()
    }

    func test_load_setsSpectralTimePitchAlgorithm() async throws {
        let engine = PlayerEngine()
        let url = try silentAssetURL(seconds: 1.0)
        await engine.load(asset: AVURLAsset(url: url))
        XCTAssertEqual(engine.player.currentItem?.audioTimePitchAlgorithm, .spectral)
    }

    /// Reuses the helper pattern from `PlayerEngineTests` — writes a tiny silent
    /// WAV to a temp dir so the player has something real to load.
    private func silentAssetURL(seconds: Double) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")
        let sampleRate = 44_100.0
        let frameCount = Int(sampleRate * seconds)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))!
        buffer.frameLength = AVAudioFrameCount(frameCount)
        try file.write(from: buffer)
        return url
    }
```

If `PlayerEngineTests.swift` already has a `silentAssetURL`/equivalent helper, factor it into a shared test util file instead of duplicating; otherwise leave it private here for now (DRY when a second copy appears).

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild test -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS' \
  -only-testing:OnlyCueTests/PlayerEnginePlaybackRateTests/test_play_appliesCustomPlaybackRate \
  -only-testing:OnlyCueTests/PlayerEnginePlaybackRateTests/test_load_setsSpectralTimePitchAlgorithm \
  2>&1 | tail -20
```

Expected: both fail — `test_load_setsSpectralTimePitchAlgorithm` shows the algorithm is `.lowQualityZeroLatency` (AVFoundation's default); `test_play_appliesCustomPlaybackRate` shows `player.rate == 1.0`.

- [ ] **Step 3: Wire `playbackRate` into `play()` and set pitch algorithm in `load(asset:)`**

In `OnlyCue/Media/PlayerEngine.swift`:

Replace the body of `load(asset:)` (lines 45–53) with:

```swift
    func load(asset: AVAsset) async {
        let item = AVPlayerItem(asset: asset)
        item.audioTimePitchAlgorithm = .spectral
        player.replaceCurrentItem(with: item)
        rate = 0
        currentTime = 0
        if let cmDuration = try? await asset.load(.duration) {
            duration = CMTimeGetSeconds(cmDuration)
        }
    }
```

Replace the body of `play()` (lines 63–66) with:

```swift
    func play() {
        player.play()
        // Calling `play()` first ensures the time control status flips before we
        // override the rate; otherwise AVPlayer can snap back to 1.0.
        player.rate = playbackRate
        rate = player.rate
    }
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild test -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS' \
  -only-testing:OnlyCueTests/PlayerEnginePlaybackRateTests \
  -only-testing:OnlyCueTests/PlayerEngineTests \
  2>&1 | tail -25
```

Expected: all `PlayerEnginePlaybackRateTests` pass AND the pre-existing `PlayerEngineTests.test_playSetsRate` still passes (it asserts `engine.rate == 1.0` after `play()`, which is satisfied because `playbackRate` defaults to 1.0).

- [ ] **Step 5: Commit**

```bash
git add OnlyCue/Media/PlayerEngine.swift OnlyCueTests/PlayerEnginePlaybackRateTests.swift
git commit -m "feat(media): apply playback rate on play and preserve pitch"
```

---

## Task 3: Add KeymapAction cases and default bindings

**Files:**
- Modify: `OnlyCue/App/KeymapAction.swift`
- Modify: `OnlyCue/App/Keymap.swift`
- Test: `OnlyCueTests/PlayerEnginePlaybackRateTests.swift` (no new test — covered by existing keymap-coverage tests in `OnlyCueTests/`, see Step 4)

- [ ] **Step 1: Add the three new cases to `KeymapAction`**

In `OnlyCue/App/KeymapAction.swift`, add after `case stepNextCue` (line 37) and before `case addCue`:

```swift
    // Document window — playback rate (rehearsal aid; never persisted to .cuelist).
    case playbackRateUp
    case playbackRateDown
    case playbackRateReset
```

Then add corresponding entries to the `displayNames` dictionary (line 68 onward), adjacent to `.stepNextCue`:

```swift
        .playbackRateUp: "Speed Up",
        .playbackRateDown: "Slow Down",
        .playbackRateReset: "Reset Speed",
```

- [ ] **Step 2: Add the default bindings to `Keymap`**

In `OnlyCue/App/Keymap.swift`, add to `defaultBindings` (around line 117, near `playPause`):

```swift
        .playbackRateUp: KeyChord(key: "]"),
        .playbackRateDown: KeyChord(key: "["),
        .playbackRateReset: KeyChord(key: "\\"),
```

- [ ] **Step 3: Run the full keymap test suite to verify coverage tests still pass**

```bash
xcodebuild test -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS' \
  -only-testing:OnlyCueTests/KeymapTests \
  -only-testing:OnlyCueTests/KeymapDocumentActionsTests \
  2>&1 | tail -30
```

Expected: all keymap tests pass. If the project has a test asserting "every `KeymapAction` has a default binding" or "every action has a display name", the new cases must satisfy it — the steps above add both.

- [ ] **Step 4: Commit**

```bash
git add OnlyCue/App/KeymapAction.swift OnlyCue/App/Keymap.swift
git commit -m "feat(app): add playback rate keymap actions"
```

---

## Task 4: Wire shortcuts in DocumentView + LTC interlock

**Files:**
- Modify: `OnlyCue/UI/DocumentView.swift`

This task adds:
- A hidden-button group binding the three shortcuts (same pattern as `transportShortcuts`).
- Notification observers so the new `Playback` menu (Task 5) can drive the engine.
- The LTC interlock: rate-change attempts are blocked when LTC is enabled; enabling LTC resets the rate.

- [ ] **Step 1: Add notification names**

In `OnlyCue/UI/DocumentView.swift`, locate the existing `extension Notification.Name { ... }` block around line 282 and add:

```swift
    static let playbackRateUp = Notification.Name("playbackRateUp")
    static let playbackRateDown = Notification.Name("playbackRateDown")
    static let playbackRateReset = Notification.Name("playbackRateReset")
    static let playbackRateInterlockBlocked = Notification.Name("playbackRateInterlockBlocked")
    static let playbackRateInterlockReset = Notification.Name("playbackRateInterlockReset")
```

The two `interlock…` names are read by `PlaybackRateBadge` (Task 6) to flash the interlock message. They have no payload.

- [ ] **Step 2: Add hidden-button shortcuts**

In `DocumentView.swift`, locate the `transportShortcuts` computed property (around line 206) and add a sibling `playbackRateShortcuts` after it:

```swift
    private var playbackRateShortcuts: some View {
        ZStack {
            Button("Speed Up") { handlePlaybackRateChange(.up) }
                .keyboardShortcut(shortcut(.playbackRateUp))
            Button("Slow Down") { handlePlaybackRateChange(.down) }
                .keyboardShortcut(shortcut(.playbackRateDown))
            Button("Reset Speed") { handlePlaybackRateChange(.reset) }
                .keyboardShortcut(shortcut(.playbackRateReset))
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    private enum PlaybackRateChange { case up, down, reset }

    private func handlePlaybackRateChange(_ change: PlaybackRateChange) {
        // LTC interlock: block any change that would leave rate != 1.0 while LTC is on.
        let ltcOn = LTCRoutingStore.shared.settings.isEnabled
        let target: Float
        switch change {
        case .up:    target = engine.playbackRate + 0.1
        case .down:  target = engine.playbackRate - 0.1
        case .reset: target = 1.0
        }
        if ltcOn && abs(target - 1.0) > 0.0001 {
            NSSound.beep()
            NotificationCenter.default.post(name: .playbackRateInterlockBlocked, object: nil)
            return
        }
        switch change {
        case .up:    engine.nudgePlaybackRate(by: 0.1)
        case .down:  engine.nudgePlaybackRate(by: -0.1)
        case .reset: engine.resetPlaybackRate()
        }
    }
```

- [ ] **Step 3: Mount the new shortcut group into the view body**

In `DocumentView.swift`, find where `transportShortcuts`, `digitShortcuts`, and `playheadStepShortcuts` are placed inside the view body (search for `transportShortcuts`). Add `playbackRateShortcuts` to that overlay/`ZStack`/`background` alongside them so the shortcuts are live whenever the document window has focus.

- [ ] **Step 4: Add notification observers for the menu-item path**

In `DocumentView.swift`, locate the existing `.onReceive(NotificationCenter.default.publisher(for: ...))` modifiers (search for `onReceive`) and add three observers on the same view that owns `transportShortcuts`:

```swift
        .onReceive(NotificationCenter.default.publisher(for: .playbackRateUp)) { _ in
            handlePlaybackRateChange(.up)
        }
        .onReceive(NotificationCenter.default.publisher(for: .playbackRateDown)) { _ in
            handlePlaybackRateChange(.down)
        }
        .onReceive(NotificationCenter.default.publisher(for: .playbackRateReset)) { _ in
            handlePlaybackRateChange(.reset)
        }
```

If the file already has many `.onReceive` modifiers grouped, place these adjacent to the existing transport notifications (`.importMediaRequested`, etc.) for consistency.

- [ ] **Step 5: Add LTC-enable reset side effect**

Still in `DocumentView.swift`, add an `.onChange` observer for `LTCRoutingStore`'s enable flag. If `LTCRoutingStore` is referenced as `@ObservedObject` in this view (the transport bar uses `.shared`), introduce the binding:

```swift
    @ObservedObject private var ltcRoutingStore = LTCRoutingStore.shared
```

Then add this view modifier (place near the other `.onChange` / `.onReceive` modifiers):

```swift
        .onChange(of: ltcRoutingStore.settings.isEnabled) { _, newValue in
            // Spec §3.5 (2): turning LTC on while rate != 1.0× resets rate first.
            guard newValue, abs(engine.playbackRate - 1.0) > 0.0001 else { return }
            engine.resetPlaybackRate()
            NotificationCenter.default.post(name: .playbackRateInterlockReset, object: nil)
        }
```

If `LTCRoutingStore.shared.settings.isEnabled` is not directly observable (e.g., `settings` is a value type and the store doesn't republish), inspect `LTCRoutingStore` and adjust: observe the `@Published` property that fires when enable toggles, or add one if necessary. **Do not** add a polling timer. If a change is required to `LTCRoutingStore`, do it in this step and commit it together.

- [ ] **Step 6: Build to verify**

```bash
xcodebuild build -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS' 2>&1 | tail -15
```

Expected: build succeeds.

- [ ] **Step 7: Commit**

```bash
git add OnlyCue/UI/DocumentView.swift OnlyCue/LTC/LTCRoutingStore.swift
git commit -m "feat(app): wire playback rate shortcuts and LTC interlock"
```

(`LTCRoutingStore.swift` is included only if you had to touch it in Step 5; otherwise drop it from the `git add`.)

---

## Task 5: Add the Playback menu

**Files:**
- Modify: `OnlyCue/App/AppCommands.swift`

- [ ] **Step 1: Add `CommandMenu("Playback")`**

In `OnlyCue/App/AppCommands.swift`, inside `var body: some Commands { ... }`, after the `CommandGroup(after: .sidebar) { ... }` block (it ends around line 139) and before `CommandMenu("Tools")` (line 141), add:

```swift
        CommandMenu("Playback") {
            Button("Speed Up") {
                NotificationCenter.default.post(name: .playbackRateUp, object: nil)
            }
            .keyboardShortcut(shortcut(.playbackRateUp))
            .accessibilityIdentifier("playbackRateUpMenuItem")

            Button("Slow Down") {
                NotificationCenter.default.post(name: .playbackRateDown, object: nil)
            }
            .keyboardShortcut(shortcut(.playbackRateDown))
            .accessibilityIdentifier("playbackRateDownMenuItem")

            Button("Reset Speed") {
                NotificationCenter.default.post(name: .playbackRateReset, object: nil)
            }
            .keyboardShortcut(shortcut(.playbackRateReset))
            .accessibilityIdentifier("playbackRateResetMenuItem")
        }
```

**Note on Play / Pause:** Per spec §4.3, Play/Pause is *not* added to this menu — `DocumentView.transportShortcuts` already binds the `playPause` shortcut on a hidden button. Adding it again here would create a duplicate `KeyboardShortcut` binding for `Space`. The Playback menu is speed-only.

**Note on LTC interlock UX:** The menu items are *not* disabled in this version. The `handlePlaybackRateChange` function (Task 4) emits the interlock signal when clicked while LTC is active. Menu-item disable-state requires a `@FocusedValue` plumbing path that's out of scope here; the audible beep + transport-bar interlock flash is sufficient.

- [ ] **Step 2: Build to verify**

```bash
xcodebuild build -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS' 2>&1 | tail -10
```

Expected: build succeeds.

- [ ] **Step 3: Manual smoke**

Open the built app, confirm `Playback` appears in the menu bar between `View` and `Window`, contains the three items with shortcuts `]` / `[` / `\` displayed, and clicking each item changes the rate (next task makes the change visible).

- [ ] **Step 4: Commit**

```bash
git add OnlyCue/App/AppCommands.swift
git commit -m "feat(app): add Playback menu with speed controls"
```

---

## Task 6: Add the transport-bar rate badge

**Files:**
- Create: `OnlyCue/UI/PlaybackRateBadge.swift`
- Modify: `OnlyCue/UI/TransportBar.swift`

- [ ] **Step 1: Create `PlaybackRateBadge`**

Create `OnlyCue/UI/PlaybackRateBadge.swift`:

```swift
import SwiftUI

/// Transport-bar rate indicator + popover. Hidden when `rate == 1.0×` outside
/// the flash window. Flashes briefly on any rate change (including back to 1.0×).
struct PlaybackRateBadge: View {

    let engine: PlayerEngine

    @State private var flashUntil: Date = .distantPast
    @State private var interlockMessage: String? = nil
    @State private var showPopover = false

    private static let flashDuration: TimeInterval = 1.2
    private static let interlockBlockedMessage = "Disable LTC to change playback rate."
    private static let interlockResetMessage = "Playback rate reset to 1.0× for LTC."

    private var rateText: String {
        // One-decimal formatting, e.g. "1.5×", "0.3×", "1.0×".
        String(format: "%.1f×", engine.playbackRate)
    }

    private var isFlashing: Bool { Date() < flashUntil }
    private var isAtNormalRate: Bool { abs(engine.playbackRate - 1.0) < 0.0001 }
    private var isVisible: Bool { !isAtNormalRate || isFlashing || interlockMessage != nil }

    var body: some View {
        Group {
            if isVisible {
                Button { showPopover.toggle() } label: {
                    Text(interlockMessage ?? rateText)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(interlockMessage != nil ? .red : .secondary)
                        .accessibilityIdentifier("playbackRateBadge")
                }
                .buttonStyle(.plain)
                .help("Playback rate (click to adjust)")
                .popover(isPresented: $showPopover) {
                    PlaybackRatePopover(engine: engine)
                        .padding()
                }
            }
        }
        .onChange(of: engine.playbackRate) { _, _ in
            flashUntil = Date().addingTimeInterval(Self.flashDuration)
        }
        .onReceive(NotificationCenter.default.publisher(for: .playbackRateInterlockBlocked)) { _ in
            flashInterlock(Self.interlockBlockedMessage)
        }
        .onReceive(NotificationCenter.default.publisher(for: .playbackRateInterlockReset)) { _ in
            flashInterlock(Self.interlockResetMessage)
        }
    }

    private func flashInterlock(_ message: String) {
        interlockMessage = message
        let until = Date().addingTimeInterval(Self.flashDuration)
        flashUntil = until
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.flashDuration) {
            if Date() >= until {
                interlockMessage = nil
            }
        }
    }
}

private struct PlaybackRatePopover: View {

    @Bindable var engine: PlayerEngine

    private var rateBinding: Binding<Double> {
        Binding(
            get: { Double(engine.playbackRate) },
            set: { engine.setPlaybackRate(Float($0)) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(format: "Speed: %.1f×", engine.playbackRate))
                .font(.system(.body, design: .monospaced))
            Slider(
                value: rateBinding,
                in: Double(PlayerEngine.playbackRateRange.lowerBound)...Double(PlayerEngine.playbackRateRange.upperBound),
                step: Double(PlayerEngine.playbackRateStep)
            )
            .frame(width: 220)
            .accessibilityIdentifier("playbackRateSlider")
            Button("Reset to 1.0×") { engine.resetPlaybackRate() }
                .accessibilityIdentifier("playbackRateResetButton")
        }
    }
}
```

`PlayerEngine` is already `@Observable`, so the badge and popover automatically re-render when `playbackRate` changes. `@Bindable` requires the engine to remain `@Observable` (it is — line 5 of `PlayerEngine.swift`).

- [ ] **Step 2: Embed the badge in `TransportBar`**

In `OnlyCue/UI/TransportBar.swift`, inside `body` (the `HStack` starting at line 144), add the badge after the `timeReadout` `Text` and before the SMPTE block:

```swift
            PlaybackRateBadge(engine: engine)
```

- [ ] **Step 3: Build and smoke-test manually**

```bash
xcodebuild build -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS' 2>&1 | tail -10
```

Open the app, load a media file, and:
- Press `]` three times → badge reads `1.3×`.
- Press `\` → badge briefly shows `1.0×` then disappears after ~1.2s.
- Click the badge while rate ≠ 1.0× → popover opens with slider + reset.
- Enable LTC in Audio Settings while rate is 1.3× → rate snaps to 1.0× and badge briefly shows the "reset for LTC" message in red.
- With LTC still on, press `]` → audible beep, badge briefly shows "Disable LTC to change playback rate." in red.

- [ ] **Step 4: Commit**

```bash
git add OnlyCue/UI/PlaybackRateBadge.swift OnlyCue/UI/TransportBar.swift
git commit -m "feat(ui): add playback rate badge to transport bar"
```

If `project.yml` uses an explicit `sources` list (rather than auto-discovery), add `PlaybackRateBadge.swift` to it and re-run `xcodegen generate` before this commit, then include the regenerated project in the same commit.

---

## Task 7: UI smoke tests

**Files:**
- Create: `OnlyCueUITests/PlaybackSpeedUITests.swift`

- [ ] **Step 1: Write the UI tests**

Create `OnlyCueUITests/PlaybackSpeedUITests.swift`:

```swift
import XCTest

final class PlaybackSpeedUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func test_playbackMenu_hasSpeedItems() {
        let app = XCUIApplication()
        app.launch()
        let playbackMenu = app.menuBars.menus["Playback"]
        XCTAssertTrue(playbackMenu.menuItems["playbackRateUpMenuItem"].exists)
        XCTAssertTrue(playbackMenu.menuItems["playbackRateDownMenuItem"].exists)
        XCTAssertTrue(playbackMenu.menuItems["playbackRateResetMenuItem"].exists)
    }

    func test_speedUpMenuItem_showsBadgeWithIncreasedRate() throws {
        let app = XCUIApplication()
        // Seed: launch with a pre-loaded media item so the document is interactive.
        // Reuse the seed convention from `UITestSeedHandler` — same as other UI tests
        // in this target. See OnlyCueUITests for examples of the seed string.
        app.launchArguments += ["--ui-test-seed", "single-media-loaded"]
        app.launch()

        // Click Playback → Speed Up three times via the menu (cmd-paths are
        // independent of any future shortcut rebind).
        for _ in 0..<3 {
            app.menuBars.menus["Playback"].menuItems["playbackRateUpMenuItem"].click()
        }

        let badge = app.staticTexts["playbackRateBadge"]
        XCTAssertTrue(badge.waitForExistence(timeout: 2))
        XCTAssertEqual(badge.label, "1.3×")

        // Reset.
        app.menuBars.menus["Playback"].menuItems["playbackRateResetMenuItem"].click()
        // After flash window, badge disappears.
        XCTAssertTrue(badge.waitForNonExistence(timeout: 2))
    }

    func test_badgeClick_opensPopoverWithSliderAndReset() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-seed", "single-media-loaded"]
        app.launch()

        app.menuBars.menus["Playback"].menuItems["playbackRateUpMenuItem"].click()
        let badge = app.staticTexts["playbackRateBadge"]
        XCTAssertTrue(badge.waitForExistence(timeout: 2))
        badge.click()

        XCTAssertTrue(app.sliders["playbackRateSlider"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["playbackRateResetButton"].exists)
    }
}
```

Confirm the `--ui-test-seed` value (e.g., `single-media-loaded`) matches an actual case in `OnlyCue/App/UITestSeedHandler.swift`. If the existing seed handler uses a different name, replace `single-media-loaded` with the matching one. If no suitable seed exists, add one (single short bundled audio file loaded into a fresh document) using the same pattern as existing seeds — keep the addition minimal.

- [ ] **Step 2: Run the UI tests**

```bash
xcodebuild test -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS' \
  -only-testing:OnlyCueUITests/PlaybackSpeedUITests \
  2>&1 | tail -30
```

Expected: 3 tests pass.

If `test_speedUpMenuItem_showsBadgeWithIncreasedRate` flakes on `waitForNonExistence` (the flash takes 1.2s; the timeout is 2s — tight but should hold), bump the timeout to 3s rather than reducing the flash duration.

- [ ] **Step 3: Commit**

```bash
git add OnlyCueUITests/PlaybackSpeedUITests.swift
git commit -m "test(ui): smoke tests for playback speed control"
```

---

## Task 8: Verification and lint

- [ ] **Step 1: Run the full test suite**

```bash
xcodebuild test -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS' 2>&1 | tail -30
```

Expected: all tests pass — especially `PlayerEngineTests`, `KeymapTests`, `KeymapDocumentActionsTests`, the new `PlayerEnginePlaybackRateTests`, and `PlaybackSpeedUITests`.

- [ ] **Step 2: Run SwiftLint**

```bash
swiftlint --quiet 2>&1 | tail -30
```

Expected: no new warnings introduced by the files touched in this plan. Address any warnings inline (typically: long lines, force-unwraps in tests are tolerated per existing config).

- [ ] **Step 3: Final manual verification against spec §3**

Walk through these flows manually (already done piecewise during Task 6 Step 3, but consolidate here):

- Range/step: starting at 1.0×, press `]` and `[` repeatedly — confirm the badge values walk by 0.1, stop at 3.0 and 0.1, never go beyond.
- Pitch: at 0.5× and 2.0×, audio sounds slower/faster without chipmunk pitch shift.
- Sticky across stop/play: at 0.5×, hit Space twice (pause then play); badge stays at 0.5×.
- Sticky across media switch: at 0.5×, switch the active media; badge stays at 0.5×.
- Reset on project switch: at 0.5×, open a different `.cuelist`; new document opens at 1.0×.
- Reset on app relaunch: at 0.5×, quit, relaunch; document opens at 1.0×.
- LTC interlock (blocked): with LTC on, press `]` → beep + red interlock message; rate stays at 1.0×.
- LTC interlock (auto-reset): with rate at 0.5× and LTC off, enable LTC → rate snaps to 1.0× + red reset message.

- [ ] **Step 4: Open PR**

Use the `gh-pr` skill. PR type is `feat`. Link the spec in the OnlyCue verification footer (`docs/superpowers/specs/2026-05-15-playback-speed-control-design.md`).

---

## Self-review notes

- Spec §3.1 range/step — Task 1.
- Spec §3.2 pitch — Task 2.
- Spec §3.3 play vs. pause behavior — Task 2 (Step 3 sets `player.rate = playbackRate` inside `play()`).
- Spec §3.4 reset triggers — Task 4 (LTC enable) + automatic by virtue of no persistence (relaunch, project switch — `PlayerEngine` is rebuilt per document).
- Spec §3.5 LTC interlock — Task 4 (both directions).
- Spec §4.1 PlayerEngine API — Task 1 + Task 2.
- Spec §4.2 keymap actions — Task 3.
- Spec §4.3 Playback menu — Task 5 (Play/Pause deliberately omitted per spec fallback in §4.3 / §7).
- Spec §4.4 transport bar badge + popover — Task 6.
- Spec §5 out-of-scope confirmations — nothing touched: no schema, no CueCommands, no tempo / LTC encoder / OSC / waveform changes.
- Spec §6.1 unit tests — Task 1, Task 2.
- Spec §6.2 UI smoke — Task 7.
- Spec §7 open questions — answered inline: menu placement (between View and Window via `CommandMenu` natural ordering); Play/Pause omitted from new menu; HUD reuses the badge slot (no global toast system existed); badge fade matches `withAnimation` defaults via `onChange` flash window.
