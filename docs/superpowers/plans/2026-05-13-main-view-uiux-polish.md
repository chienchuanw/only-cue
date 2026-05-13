# Main View UI/UX Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Polish the OnlyCue main document view — rename to "Only Cue", declutter the pane, render a high-resolution DAW-style waveform, make the playhead glide smoothly, and add click-to-seek.

**Architecture:** Six independent leaf tasks against `DocumentView`, the waveform stack (`WaveformGenerator`, `WaveformView`, `WaveformContainer`, `WaveformPlayheadLayer`, `PlayheadOverlay`), and `PlayerEngine`. Pure logic (peak bucketing, x↔time mapping, playhead interpolation) is extracted into small testable helpers; SwiftUI views stay thin.

**Tech Stack:** Swift 6, SwiftUI, AVFoundation, XCTest. macOS 14+. Project generated via XcodeGen (`project.yml`).

**Conventions:** Conventional Commits, lowercase after prefix, imperative. No `Co-Authored-By` trailers. TDD: failing test first, separate commit when practical. Build/test: `xcodegen generate` then `xcodebuild -scheme OnlyCue -destination 'platform=macOS' test` (or run specific tests in Xcode). New `.swift` files under `OnlyCue/` and `OnlyCueTests/` are picked up by the existing folder rules in `project.yml` — no `project.yml` edit needed unless you add a new top-level folder.

---

## File Structure

| File | Responsibility | Action |
|---|---|---|
| `OnlyCue/Resources/Info.plist` | `CFBundleDisplayName` = "Only Cue" | Modify |
| `OnlyCue/UI/FirstLaunchSheet.swift` | "Welcome to Only Cue" | Modify |
| `OnlyCue/UI/DocumentView.swift` | Remove title/summary/cueCount; gate Import button + hints to empty state | Modify |
| `OnlyCue/UI/DocumentEmptyState.swift` | New: the no-media onboarding view (Import button + hints) | Create |
| `OnlyCue/Media/WaveformPeakBucketer.swift` | New: pure function — downsample N peaks → M pixel buckets (max per bucket) | Create |
| `OnlyCue/UI/WaveformView.swift` | Draw a filled mirrored envelope using the bucketer | Modify |
| `OnlyCue/UI/WaveformContainer.swift` | Bump default `resolution`; pass pixel width to `WaveformView` | Modify |
| `OnlyCue/Media/PlayerEngine.swift` | Time observer interval 0.1s → 1/60s | Modify |
| `OnlyCue/UI/PlayheadInterpolator.swift` | New: pure function — interpolate rendered playhead time from last observed time + rate + elapsed | Create |
| `OnlyCue/UI/WaveformPlayheadLayer.swift` | Drive playhead from interpolator; tap-to-seek on body; drag-to-scrub on playhead line; hand cursor | Modify |
| `OnlyCue/UI/CueMarkersGeometry.swift` | Add `time(forX:width:duration:)` inverse mapping | Modify |
| `OnlyCueTests/WaveformPeakBucketerTests.swift` | Bucketer tests | Create |
| `OnlyCueTests/PlayheadInterpolatorTests.swift` | Interpolator tests | Create |
| `OnlyCueTests/CueMarkersGeometryTests.swift` | x↔time mapping tests (create if absent, else extend) | Create/Modify |
| `OnlyCueUITests/MainViewDeclutterUITests.swift` | UI: removed labels absent; empty state present | Create |
| `OnlyCueUITests/WaveformClickToSeekUITests.swift` | UI: click moves playhead; drag still scrubs | Create |

---

## Task 1: Rename "OnlyCue" → "Only Cue" (display strings only)

**Files:**
- Modify: `OnlyCue/Resources/Info.plist`
- Modify: `OnlyCue/UI/FirstLaunchSheet.swift:18`
- Modify: `OnlyCue/UI/DocumentView.swift:68` (this line is also removed in Task 2 — if Task 2 is done first, skip the DocumentView edit here)

No automated test — this is verified manually. Keep `CFBundleName`, `CFBundleIdentifier`, `com.onlycue.cuelist`, module name, and all `OnlyCue.*` notification names unchanged.

- [ ] **Step 1: Add `CFBundleDisplayName` to Info.plist**

In `OnlyCue/Resources/Info.plist`, inside the top-level `<dict>`, add after the `CFBundleName` entry:

```xml
    <key>CFBundleDisplayName</key>
    <string>Only Cue</string>
```

- [ ] **Step 2: Update FirstLaunchSheet copy**

In `OnlyCue/UI/FirstLaunchSheet.swift`, line 18:

```swift
            Text("Welcome to Only Cue")
```

- [ ] **Step 3: Update the in-pane title string**

In `OnlyCue/UI/DocumentView.swift`, line ~68:

```swift
            Text("Only Cue")
```

(If Task 2 runs first this `Text` is deleted entirely; in that case this step is a no-op.)

- [ ] **Step 4: Regenerate the project and build**

Run: `xcodegen generate && xcodebuild -scheme OnlyCue -destination 'platform=macOS' build`
Expected: build succeeds.

- [ ] **Step 5: Manual verification**

Run the app. Confirm the macOS menu bar reads "Only Cue", the About box title reads "Only Cue", and the first-launch sheet reads "Welcome to Only Cue". Open an existing `.cuelist` document — it still opens.

- [ ] **Step 6: Commit**

```bash
git add OnlyCue/Resources/Info.plist OnlyCue/UI/FirstLaunchSheet.swift OnlyCue/UI/DocumentView.swift
git commit -m "chore: rename user-facing app name to \"Only Cue\""
```

---

## Task 2: Declutter the main pane (minimal)

**Files:**
- Create: `OnlyCue/UI/DocumentEmptyState.swift`
- Modify: `OnlyCue/UI/DocumentView.swift` (`mainPane`, lines ~65–134)
- Create: `OnlyCueUITests/MainViewDeclutterUITests.swift`

Loaded state becomes: `PreviewPane` → `TransportBar` → "Add Cue" button. Empty state becomes: a centered onboarding view with "Import Media…" + the shortcut hints.

- [ ] **Step 1: Write the failing UI test**

Create `OnlyCueUITests/MainViewDeclutterUITests.swift`:

```swift
import XCTest

final class MainViewDeclutterUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func test_loadedPaneHidesTitleSummaryAndCueCount() throws {
        let app = XCUIApplication()
        app.launch()
        // With no media imported the app shows the empty state, which DOES
        // contain the shortcut hints and the Import button.
        XCTAssertTrue(app.staticTexts["documentShortcutHints"].exists)
        XCTAssertTrue(app.buttons["importMediaButton"].exists)
        // The removed loaded-state chrome must not be present anywhere.
        XCTAssertFalse(app.staticTexts["documentTitle"].exists)
        XCTAssertFalse(app.staticTexts["mediaSummary"].exists)
        XCTAssertFalse(app.staticTexts["cueCount"].exists)
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `xcodebuild -scheme OnlyCue -destination 'platform=macOS' test -only-testing:OnlyCueUITests/MainViewDeclutterUITests`
Expected: FAIL — `documentTitle` / `mediaSummary` / `cueCount` still exist.

- [ ] **Step 3: Create the empty-state view**

Create `OnlyCue/UI/DocumentEmptyState.swift`:

```swift
import SwiftUI

/// Shown in the main pane when no media item is active. Carries the onboarding
/// affordances that used to live permanently in the loaded pane: the Import
/// button and the keyboard-shortcut cheatsheet.
struct DocumentEmptyState: View {

    let onImport: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("No media imported")
                .font(.title3)
                .foregroundStyle(.secondary)
            Button("Import Media…") { onImport() }
                .accessibilityIdentifier("importMediaButton")
                .help("Import Media (⌘O)")
            DocumentShortcutHints()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("documentEmptyState")
    }
}
```

- [ ] **Step 4: Rewrite `mainPane` in `DocumentView.swift`**

Replace the body of `private var mainPane: some View` (currently lines ~65–134) with:

```swift
    private var mainPane: some View {
        let activeItem = document.model.activeItem
        return Group {
            if activeItem == nil {
                DocumentEmptyState(onImport: { showImporter = true })
            } else {
                VStack(spacing: 12) {
                    PreviewPane(
                        document: document,
                        engine: engine,
                        selectedCueIDs: cueSelection,
                        onSelectCue: { cueSelection = [$0] },
                        onToggleCue: { cueSelection.formSymmetricDifference([$0]) }
                    )

                    TransportBar(
                        engine: engine,
                        cues: activeItem?.cues ?? [],
                        mediaDuration: activeItem?.media.duration ?? 0,
                        timecodeSettings: document.model.timecodeSettings
                    )
                    .padding(.top, 4)

                    Button("Add Cue") { addCueAtPlayhead() }
                        .accessibilityIdentifier("addCueButton")
                        .keyboardShortcut(shortcut(.addCue))

                    transportShortcuts
                    digitShortcuts
                    playheadStepShortcuts
                }
            }
        }
        .frame(minWidth: 560, minHeight: 480)
        .padding()
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: MediaImporter.allowedContentTypes,
            allowsMultipleSelection: true,
            onCompletion: handlePickerResult
        )
        .dropDestination(for: URL.self) { urls, _ in
            guard !urls.isEmpty else { return false }
            importURLs(urls)
            return true
        }
        .alert(item: $pendingAlert, content: alertContent)
        .onReceive(NotificationCenter.default.publisher(for: .importMediaRequested)) { _ in
            showImporter = true
        }
        .templateMenuReceiver(
            document: document,
            pendingErrorMessage: pendingAlertMessageBinding,
            undoManager: undoManager
        )
    }
```

Then delete the now-unused `mediaSummary(_:)` helper (lines ~166–176). Leave `transportShortcuts`, `digitShortcuts`, `playheadStepShortcuts`, and everything else in `DocumentView` untouched. Note: the digit/step shortcut views already `.disabled(document.model.activeItem == nil)`, but since they now only render when `activeItem != nil`, that's harmless — leave it.

- [ ] **Step 5: Regenerate, build, run the UI test**

Run: `xcodegen generate && xcodebuild -scheme OnlyCue -destination 'platform=macOS' test -only-testing:OnlyCueUITests/MainViewDeclutterUITests`
Expected: PASS.

- [ ] **Step 6: Run the full test suite**

Run: `xcodebuild -scheme OnlyCue -destination 'platform=macOS' test`
Expected: PASS (watch for any other UI test that referenced `documentTitle` / `mediaSummary` / `cueCount` — if one breaks, update it to match the new layout).

- [ ] **Step 7: Commit**

```bash
git add OnlyCue/UI/DocumentEmptyState.swift OnlyCue/UI/DocumentView.swift OnlyCueUITests/MainViewDeclutterUITests.swift
git commit -m "feat(ui): declutter main pane; move import + hints to empty state"
```

---

## Task 3: High-resolution waveform peaks + render-time bucketing

**Files:**
- Create: `OnlyCue/Media/WaveformPeakBucketer.swift`
- Create: `OnlyCueTests/WaveformPeakBucketerTests.swift`
- Modify: `OnlyCue/UI/WaveformContainer.swift:7` (default `resolution`)

The generator already produces `resolution` peaks; we just raise the default count. The bucketer is the new pure helper the renderer (Task 4) will use.

- [ ] **Step 1: Write the failing bucketer test**

Create `OnlyCueTests/WaveformPeakBucketerTests.swift`:

```swift
import XCTest
@testable import OnlyCue

final class WaveformPeakBucketerTests: XCTestCase {

    func test_widthEqualToCount_returnsInputUnchanged() {
        let peaks: [Float] = [0.1, 0.9, 0.4, 0.7]
        XCTAssertEqual(WaveformPeakBucketer.bucket(peaks: peaks, into: 4), peaks)
    }

    func test_downsample_takesMaxPerBucket() {
        // 8 peaks into 2 buckets -> [max of first 4, max of last 4]
        let peaks: [Float] = [0.1, 0.5, 0.2, 0.3, 0.9, 0.1, 0.4, 0.2]
        XCTAssertEqual(WaveformPeakBucketer.bucket(peaks: peaks, into: 2), [0.5, 0.9])
    }

    func test_unevenDivision_lastBucketAbsorbsRemainder() {
        // 5 peaks into 2 buckets -> bucket0 = max(peaks[0..<2]) ... actually we
        // distribute by ceil so bucket0 spans 3, bucket1 spans 2.
        let peaks: [Float] = [0.2, 0.8, 0.1, 0.3, 0.9]
        XCTAssertEqual(WaveformPeakBucketer.bucket(peaks: peaks, into: 2), [0.8, 0.9])
    }

    func test_widthGreaterThanCount_clampsToCount() {
        let peaks: [Float] = [0.3, 0.6]
        XCTAssertEqual(WaveformPeakBucketer.bucket(peaks: peaks, into: 10), peaks)
    }

    func test_emptyPeaks_returnsEmpty() {
        XCTAssertEqual(WaveformPeakBucketer.bucket(peaks: [], into: 100), [])
    }

    func test_zeroOrNegativeWidth_returnsEmpty() {
        XCTAssertEqual(WaveformPeakBucketer.bucket(peaks: [0.1, 0.2], into: 0), [])
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `xcodebuild -scheme OnlyCue -destination 'platform=macOS' test -only-testing:OnlyCueTests/WaveformPeakBucketerTests`
Expected: FAIL — `WaveformPeakBucketer` does not exist.

- [ ] **Step 3: Implement the bucketer**

Create `OnlyCue/Media/WaveformPeakBucketer.swift`:

```swift
import Foundation

/// Downsamples a high-resolution peak array to the number of horizontal pixels
/// currently on screen, taking the maximum magnitude within each pixel bucket so
/// transients aren't averaged away (the rendering trick DAWs use).
enum WaveformPeakBucketer {

    /// - Parameters:
    ///   - peaks: source magnitudes in `0...1`.
    ///   - width: target column count (typically the on-screen pixel width).
    /// - Returns: `min(width, peaks.count)` magnitudes, each the max of its bucket.
    ///   Returns the input unchanged when `width >= peaks.count`, and `[]` when
    ///   `peaks` is empty or `width <= 0`.
    static func bucket(peaks: [Float], into width: Int) -> [Float] {
        guard !peaks.isEmpty, width > 0 else { return [] }
        guard width < peaks.count else { return peaks }

        let perBucket = Int((Double(peaks.count) / Double(width)).rounded(.up))
        var result: [Float] = []
        result.reserveCapacity(width)
        var start = 0
        for _ in 0..<width {
            guard start < peaks.count else { break }
            let end = min(start + perBucket, peaks.count)
            result.append(peaks[start..<end].max() ?? 0)
            start = end
        }
        return result
    }
}
```

(Note: with `ceil` bucketing the final buckets may be empty when `width` doesn't divide evenly the other way; the `guard start < peaks.count` + `break` handles that, so `result.count` may be slightly less than `width` — that's fine for rendering. The `test_unevenDivision` case: 5 peaks, width 2 → perBucket = ceil(2.5) = 3 → bucket0 = max(peaks[0..<3]) = 0.8, bucket1 = max(peaks[3..<5]) = 0.9. ✓)

- [ ] **Step 4: Run the test to verify it passes**

Run: `xcodebuild -scheme OnlyCue -destination 'platform=macOS' test -only-testing:OnlyCueTests/WaveformPeakBucketerTests`
Expected: PASS.

- [ ] **Step 5: Raise the default waveform resolution**

In `OnlyCue/UI/WaveformContainer.swift`, line 7:

```swift
    var resolution: Int = 12_000
```

Rationale: at max zoom 16× with a ~750pt-wide waveform the content is ~12k px; ~12k source peaks gives roughly 1 peak/px there and the bucketer collapses it cleanly at lower zoom. The on-disk cache grows from ~2 KB to ~48 KB per track; the cache key already includes `resolution`, so stale 512-entry files are simply ignored and regenerated.

- [ ] **Step 6: Regenerate, build, run waveform-related tests**

Run: `xcodegen generate && xcodebuild -scheme OnlyCue -destination 'platform=macOS' test -only-testing:OnlyCueTests/WaveformPeakBucketerTests -only-testing:OnlyCueTests/WaveformGeneratorTests -only-testing:OnlyCueTests/WaveformCacheTests`
Expected: PASS. (If `WaveformCacheTests` hard-codes `resolution: 512` it still passes — it tests round-tripping at whatever resolution it picks, not the container default.)

- [ ] **Step 7: Commit**

```bash
git add OnlyCue/Media/WaveformPeakBucketer.swift OnlyCueTests/WaveformPeakBucketerTests.swift OnlyCue/UI/WaveformContainer.swift
git commit -m "feat(media): high-resolution waveform peaks + pixel-bucketing helper"
```

---

## Task 4: Filled mirrored-envelope waveform rendering

**Files:**
- Modify: `OnlyCue/UI/WaveformView.swift` (full rewrite of `body`)
- Modify: `OnlyCue/UI/WaveformContainer.swift` (pass nothing new — `WaveformView` reads its own `size` via `Canvas`)

`WaveformView` already receives the full peak array and `verticalZoom`. Replace the per-peak rounded-bar loop with: bucket to `size.width`, build one closed path mirrored about the centre line, fill it.

- [ ] **Step 1: Rewrite `WaveformView`**

Replace the entire contents of `OnlyCue/UI/WaveformView.swift`:

```swift
import SwiftUI

/// Renders the audio waveform as a filled, mirrored amplitude envelope (the
/// continuous "blob" look used by DAWs) rather than discrete bars. The source
/// `peaks` array is high-resolution; `WaveformPeakBucketer` collapses it to the
/// pixel width actually on screen so detail scales with horizontal zoom.
struct WaveformView: View {

    let peaks: [Float]
    var color: Color = .accentColor
    var verticalZoom: CGFloat = 1

    private static let minHairline: CGFloat = 0.5

    var body: some View {
        Canvas { context, size in
            guard !peaks.isEmpty, size.width > 0, size.height > 0 else { return }

            let columns = WaveformPeakBucketer.bucket(peaks: peaks, into: Int(size.width.rounded()))
            guard !columns.isEmpty else { return }

            let midY = size.height / 2
            let dx = size.width / CGFloat(columns.count)

            func halfHeight(_ peak: Float) -> CGFloat {
                min(max(CGFloat(peak) * midY * verticalZoom, Self.minHairline), midY)
            }

            var path = Path()
            // Top contour, left -> right.
            for (index, peak) in columns.enumerated() {
                let x = CGFloat(index) * dx
                let y = midY - halfHeight(peak)
                if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            // Close across the right edge and run the bottom contour right -> left.
            let lastX = CGFloat(columns.count - 1) * dx
            path.addLine(to: CGPoint(x: lastX, y: midY + halfHeight(columns[columns.count - 1])))
            for index in stride(from: columns.count - 1, through: 0, by: -1) {
                let x = CGFloat(index) * dx
                path.addLine(to: CGPoint(x: x, y: midY + halfHeight(columns[index])))
            }
            path.closeSubpath()

            context.fill(path, with: .color(context.environment.colorScheme == .dark ? color : color))
        }
        .accessibilityIdentifier("waveform")
    }
}
```

(The `colorScheme` ternary is a no-op placeholder kept simple — `context.fill(path, with: .color(color))` is equivalent; if SwiftLint flags the redundant ternary, replace that line with `context.fill(path, with: .color(color))`.)

- [ ] **Step 2: Regenerate and build**

Run: `xcodegen generate && xcodebuild -scheme OnlyCue -destination 'platform=macOS' build`
Expected: build succeeds.

- [ ] **Step 3: Run the full test suite**

Run: `xcodebuild -scheme OnlyCue -destination 'platform=macOS' test`
Expected: PASS. (No unit test asserts pixel output; the `waveform` accessibility id is unchanged so any UI test referencing it still works.)

- [ ] **Step 4: Manual verification**

Run the app, import an audio file. The waveform is a continuous filled shape, not bars. Zoom in (⌘= a few times / pinch): more amplitude detail appears rather than the shape just being magnified. Vertical zoom still scales it. Scrolling at zoom still works.

- [ ] **Step 5: Commit**

```bash
git add OnlyCue/UI/WaveformView.swift
git commit -m "feat(ui): render waveform as a filled mirrored envelope"
```

---

## Task 5: Smooth playhead — faster observer + display-link interpolation

**Files:**
- Modify: `OnlyCue/Media/PlayerEngine.swift` (`observeTime`, lines ~77–90)
- Create: `OnlyCue/UI/PlayheadInterpolator.swift`
- Create: `OnlyCueTests/PlayheadInterpolatorTests.swift`
- Modify: `OnlyCue/UI/WaveformPlayheadLayer.swift` and `OnlyCue/UI/PlayheadOverlay.swift` (drive `x` from interpolated time via `TimelineView(.animation)`)

The interpolator is a pure function: given the last observed `(time, wallClock)`, the current `wallClock`, the `rate`, and `duration`, return the time to render. `WaveformPlayheadLayer` wraps its geometry in `TimelineView(.animation)` so the closure re-evaluates every frame while playing.

- [ ] **Step 1: Write the failing interpolator test**

Create `OnlyCueTests/PlayheadInterpolatorTests.swift`:

```swift
import XCTest
@testable import OnlyCue

final class PlayheadInterpolatorTests: XCTestCase {

    func test_paused_returnsObservedTimeUnchanged() {
        let r = PlayheadInterpolator.renderedTime(
            observedTime: 12.0, observedAt: 100.0, now: 105.0, rate: 0, duration: 200
        )
        XCTAssertEqual(r, 12.0, accuracy: 1e-9)
    }

    func test_playingAtUnitRate_advancesByElapsedWallClock() {
        let r = PlayheadInterpolator.renderedTime(
            observedTime: 12.0, observedAt: 100.0, now: 100.25, rate: 1, duration: 200
        )
        XCTAssertEqual(r, 12.25, accuracy: 1e-9)
    }

    func test_playingAtDoubleRate_advancesTwiceAsFast() {
        let r = PlayheadInterpolator.renderedTime(
            observedTime: 12.0, observedAt: 100.0, now: 100.5, rate: 2, duration: 200
        )
        XCTAssertEqual(r, 13.0, accuracy: 1e-9)
    }

    func test_clampsToDuration() {
        let r = PlayheadInterpolator.renderedTime(
            observedTime: 199.9, observedAt: 100.0, now: 101.0, rate: 1, duration: 200
        )
        XCTAssertEqual(r, 200.0, accuracy: 1e-9)
    }

    func test_clampsToZero() {
        let r = PlayheadInterpolator.renderedTime(
            observedTime: 0.05, observedAt: 100.0, now: 100.5, rate: -1, duration: 200
        )
        XCTAssertEqual(r, 0.0, accuracy: 1e-9)
    }

    func test_negativeElapsed_isTreatedAsZero() {
        // Clock skew / stale sample: never run the playhead backwards from drift.
        let r = PlayheadInterpolator.renderedTime(
            observedTime: 12.0, observedAt: 100.0, now: 99.0, rate: 1, duration: 200
        )
        XCTAssertEqual(r, 12.0, accuracy: 1e-9)
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `xcodebuild -scheme OnlyCue -destination 'platform=macOS' test -only-testing:OnlyCueTests/PlayheadInterpolatorTests`
Expected: FAIL — `PlayheadInterpolator` does not exist.

- [ ] **Step 3: Implement the interpolator**

Create `OnlyCue/UI/PlayheadInterpolator.swift`:

```swift
import Foundation

/// Computes the playhead time to *render* between periodic time-observer ticks.
/// The observer remains the source of truth; this just slides the visible
/// playhead forward by `rate × elapsedWallClock` so it glides at the display's
/// refresh rate instead of stepping. Snaps back to the true value on each tick.
enum PlayheadInterpolator {

    static func renderedTime(
        observedTime: TimeInterval,
        observedAt: TimeInterval,
        now: TimeInterval,
        rate: Double,
        duration: TimeInterval
    ) -> TimeInterval {
        guard rate != 0 else { return clamp(observedTime, duration) }
        let elapsed = max(now - observedAt, 0)
        return clamp(observedTime + rate * elapsed, duration)
    }

    private static func clamp(_ t: TimeInterval, _ duration: TimeInterval) -> TimeInterval {
        min(max(t, 0), max(duration, 0))
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `xcodebuild -scheme OnlyCue -destination 'platform=macOS' test -only-testing:OnlyCueTests/PlayheadInterpolatorTests`
Expected: PASS.

- [ ] **Step 5: Speed up the time observer and record the observation timestamp**

In `OnlyCue/Media/PlayerEngine.swift`:

Add a stored property near `currentTime` (line ~8):

```swift
    private(set) var currentTime: TimeInterval = 0
    /// `CACurrentMediaTime()` captured when `currentTime` was last updated by the
    /// periodic observer — the anchor `PlayheadInterpolator` slides forward from.
    private(set) var currentTimeObservedAt: TimeInterval = CACurrentMediaTime()
```

Add `import QuartzCore` at the top of the file if not already imported (for `CACurrentMediaTime`).

Replace `observeTime()` (lines ~77–90):

```swift
    private func observeTime() {
        let interval = CMTime(seconds: 1.0 / 60.0, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.currentTime = CMTimeGetSeconds(time)
                self.currentTimeObservedAt = CACurrentMediaTime()
                self.rate = self.player.rate
            }
        }
    }
```

Also in `seek(to:)` (line ~71), after setting `currentTime = seconds`, add `currentTimeObservedAt = CACurrentMediaTime()` so a seek doesn't leave the interpolator anchored to a stale timestamp.

- [ ] **Step 6: Drive the rendered playhead from the interpolator**

In `OnlyCue/UI/WaveformPlayheadLayer.swift`, wrap the geometry in a `TimelineView(.animation)` and compute `displayedTime` from the interpolator when not scrubbing. Replace the `body`:

```swift
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            TimelineView(.animation) { timeline in
                let displayedTime = renderedTime(now: timeline.date)
                let x = CueMarkersGeometry.position(
                    forTime: displayedTime,
                    width: width,
                    duration: duration
                )
                ZStack(alignment: .topLeading) {
                    PlayheadOverlay(currentTime: displayedTime, duration: duration)

                    Color.clear
                        .contentShape(Rectangle())
                        .frame(width: Self.grabberWidth, height: geometry.size.height)
                        .offset(x: x - Self.grabberWidth / 2)
                        .gesture(scrubGesture(width: width))
                        .accessibilityIdentifier("playheadGrabber")
                }
                .onChange(of: displayedTime) { _, _ in maybeAutoFollow() }
            }
        }
    }

    private func renderedTime(now: Date) -> TimeInterval {
        if let scrubTime = scrub.state?.scrubTime { return scrubTime }
        return PlayheadInterpolator.renderedTime(
            observedTime: engine.currentTime,
            observedAt: engine.currentTimeObservedAt,
            now: CACurrentMediaTime(),
            rate: Double(engine.rate),
            duration: duration
        )
    }
```

(`TimelineView(.animation)` re-renders every frame; we read `CACurrentMediaTime()` directly rather than converting `timeline.date` because `currentTimeObservedAt` is on the same `CACurrentMediaTime` clock. The `timeline.date` is unused except to drive re-evaluation — that's intentional; if SwiftLint flags the unused binding, name it `_`.)

Add `import QuartzCore` to the top of `WaveformPlayheadLayer.swift`.

In `OnlyCue/UI/PlayheadOverlay.swift` — no change needed; it already takes `currentTime` as a parameter and is now fed the interpolated value.

- [ ] **Step 7: Regenerate, build, run the full suite**

Run: `xcodegen generate && xcodebuild -scheme OnlyCue -destination 'platform=macOS' test`
Expected: PASS.

- [ ] **Step 8: Manual verification**

Play a track. The playhead glides smoothly (no 0.1s stair-stepping); the time label above it updates smoothly. Pause — playhead sits exactly on the true position. Seek — playhead jumps cleanly, no rubber-banding. Auto-follow scroll at zoom still tracks.

- [ ] **Step 9: Commit**

```bash
git add OnlyCue/Media/PlayerEngine.swift OnlyCue/UI/PlayheadInterpolator.swift OnlyCueTests/PlayheadInterpolatorTests.swift OnlyCue/UI/WaveformPlayheadLayer.swift
git commit -m "feat(media): smooth playhead via faster observer + display-link interpolation"
```

---

## Task 6: Click-to-seek on the waveform body + playhead-line drag + hand cursor

**Files:**
- Modify: `OnlyCue/UI/CueMarkersGeometry.swift` (add `time(forX:width:duration:)`)
- Create: `OnlyCueTests/CueMarkersGeometryTests.swift` (or extend if it already exists — check `ls OnlyCueTests`)
- Modify: `OnlyCue/UI/WaveformPlayheadLayer.swift` (tap-to-seek; cursor on hover)
- Create: `OnlyCueUITests/WaveformClickToSeekUITests.swift`

The playhead layer fills the `contentWidth` coordinate space, so a tap's local `x` maps directly to time. Drag-to-scrub stays; we add a `NSCursor.openHand` over the playhead line and a tap recognizer over the rest.

- [ ] **Step 1: Write the failing geometry test**

Create `OnlyCueTests/CueMarkersGeometryTests.swift` (if a file with this name exists, append the `time(forX:...)` cases instead):

```swift
import XCTest
@testable import OnlyCue

final class CueMarkersGeometryTests: XCTestCase {

    func test_timeForX_mapsLinearly() {
        XCTAssertEqual(
            CueMarkersGeometry.time(forX: 50, width: 100, duration: 10),
            5, accuracy: 1e-9
        )
    }

    func test_timeForX_clampsBelowZero() {
        XCTAssertEqual(
            CueMarkersGeometry.time(forX: -20, width: 100, duration: 10),
            0, accuracy: 1e-9
        )
    }

    func test_timeForX_clampsAboveDuration() {
        XCTAssertEqual(
            CueMarkersGeometry.time(forX: 999, width: 100, duration: 10),
            10, accuracy: 1e-9
        )
    }

    func test_timeForX_zeroWidth_returnsZero() {
        XCTAssertEqual(
            CueMarkersGeometry.time(forX: 50, width: 0, duration: 10),
            0, accuracy: 1e-9
        )
    }

    func test_positionAndTime_areInverses() {
        let x = CueMarkersGeometry.position(forTime: 3.3, width: 240, duration: 12)
        XCTAssertEqual(CueMarkersGeometry.time(forX: x, width: 240, duration: 12), 3.3, accuracy: 1e-6)
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `xcodebuild -scheme OnlyCue -destination 'platform=macOS' test -only-testing:OnlyCueTests/CueMarkersGeometryTests`
Expected: FAIL — `time(forX:width:duration:)` does not exist.

- [ ] **Step 3: Add the inverse mapping**

In `OnlyCue/UI/CueMarkersGeometry.swift`, add inside `enum CueMarkersGeometry`:

```swift
    /// Inverse of `position(forTime:width:duration:)` — maps a horizontal
    /// coordinate in the waveform's content space to a clamped media time.
    static func time(forX x: CGFloat, width: CGFloat, duration: TimeInterval) -> TimeInterval {
        guard width > 0, duration > 0 else { return 0 }
        let proposed = Double(x / width) * duration
        return min(max(proposed, 0), duration)
    }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `xcodebuild -scheme OnlyCue -destination 'platform=macOS' test -only-testing:OnlyCueTests/CueMarkersGeometryTests`
Expected: PASS.

- [ ] **Step 5: Add tap-to-seek and the hand cursor in `WaveformPlayheadLayer`**

Edit `OnlyCue/UI/WaveformPlayheadLayer.swift`. Add a full-bleed transparent layer *behind* the grabber that handles taps, and put `.onContinuousHover` on the grabber to set the cursor. Inside the `ZStack(alignment: .topLeading)` from Task 5, make it:

```swift
                ZStack(alignment: .topLeading) {
                    // Tap anywhere on the waveform body -> seek there immediately.
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            seekTask?.cancel()
                            let target = CueMarkersGeometry.time(
                                forX: location.x, width: width, duration: duration
                            )
                            seekTask = Task { await engine.seek(to: target) }
                        }
                        .accessibilityIdentifier("waveformSeekSurface")

                    PlayheadOverlay(currentTime: displayedTime, duration: duration)

                    Color.clear
                        .contentShape(Rectangle())
                        .frame(width: Self.grabberWidth, height: geometry.size.height)
                        .offset(x: x - Self.grabberWidth / 2)
                        .gesture(scrubGesture(width: width))
                        .onContinuousHover { phase in
                            switch phase {
                            case .active: NSCursor.openHand.set()
                            case .ended: NSCursor.arrow.set()
                            }
                        }
                        .accessibilityIdentifier("playheadGrabber")
                }
```

In `scrubGesture(width:)` (from the existing code), set the closed-hand cursor on drag start and restore on end. Change the `.onChanged` opening and `.onEnded`:

```swift
    private func scrubGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if scrub.state == nil {
                    scrub.begin(originalTime: engine.currentTime, isPlaying: engine.isPlaying)
                    engine.pause()
                    NSCursor.closedHand.set()
                }
                scrub.update(dx: value.translation.width, width: width, duration: duration)
            }
            .onEnded { _ in
                NSCursor.arrow.set()
                guard let finished = scrub.end() else { return }
                seekTask?.cancel()
                seekTask = Task {
                    await engine.seek(to: finished.scrubTime)
                    if Task.isCancelled { return }
                    if finished.resumeOnRelease { engine.play() }
                }
            }
    }
```

Add `import AppKit` at the top of `WaveformPlayheadLayer.swift` (for `NSCursor`).

Note on disambiguation: the tap recognizer is on the *body* layer; the drag recognizer is on the narrow *grabber* layer on top of it. A press that lands on the grabber goes to the drag gesture (which, with `minimumDistance: 0`, also handles a stationary press as a zero-distance scrub that seeks to the same spot on release — harmless). A press anywhere else is a tap → seek. No competing recognizers on the same view.

- [ ] **Step 6: Write the failing UI test**

Create `OnlyCueUITests/WaveformClickToSeekUITests.swift`:

```swift
import XCTest

final class WaveformClickToSeekUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Requires a media file to be imported by the test harness. If the project's
    /// UI tests already have a fixture-import helper, use it here; otherwise this
    /// test documents the expected behavior and can be enabled once a fixture is
    /// available. We assert on the playhead overlay's existence and that a click
    /// on the left third of the waveform produces a different time label than a
    /// click on the right third.
    func test_clickingWaveformMovesPlayhead() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestImportFixtureAudio"]   // harness hook
        app.launch()

        let waveform = app.otherElements["waveformSeekSurface"]
        guard waveform.waitForExistence(timeout: 5) else {
            throw XCTSkip("No waveform surface — media fixture not loaded in this run")
        }
        let overlay = app.otherElements["playheadOverlay"]
        XCTAssertTrue(overlay.exists)

        // Click near the left edge, read the label, click near the right edge,
        // read again — the two must differ.
        waveform.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)).tap()
        let leftLabel = overlay.staticTexts.firstMatch.label
        waveform.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let rightLabel = overlay.staticTexts.firstMatch.label
        XCTAssertNotEqual(leftLabel, rightLabel)
    }
}
```

If the project has no `-uiTestImportFixtureAudio` harness hook, either (a) add one mirroring whatever pattern other `OnlyCueUITests` use to get media loaded, or (b) leave the `XCTSkip` path — the test then documents intent without failing CI. Check existing UI tests for the established fixture pattern before inventing a new one.

- [ ] **Step 7: Regenerate, build, run the full suite**

Run: `xcodegen generate && xcodebuild -scheme OnlyCue -destination 'platform=macOS' test`
Expected: PASS (the click-to-seek UI test passes or skips cleanly).

- [ ] **Step 8: Manual verification**

Import audio. Click anywhere on the waveform — playhead jumps there immediately. Press and drag the playhead line — it scrubs (audio pauses, follows the drag, resumes on release if it was playing). Cursor is a hand when hovering the playhead line, an arrow elsewhere; closed hand while dragging.

- [ ] **Step 9: Commit**

```bash
git add OnlyCue/UI/CueMarkersGeometry.swift OnlyCueTests/CueMarkersGeometryTests.swift OnlyCue/UI/WaveformPlayheadLayer.swift OnlyCueUITests/WaveformClickToSeekUITests.swift
git commit -m "feat(ui): click-to-seek on the waveform; hand cursor for playhead scrub"
```

---

## Self-Review

**Spec coverage:**
- §1 rename → Task 1 ✓
- §2 declutter (remove title/summary/cueCount, Import+hints to empty state, keep Add Cue + hidden shortcut buttons) → Task 2 ✓
- §3 high-res peaks + cache supersede → Task 3 ✓
- §3 filled mirrored envelope + render-time bucketing → Tasks 3 (bucketer) + 4 (render) ✓
- §4 faster observer + display-link interpolation → Task 5 ✓
- §5 keep floating label + transport readout → Task 5 keeps `PlayheadOverlay` label fed with interpolated time; `TransportBar` is untouched ✓
- §6 click-to-seek + drag-scrub + hand cursor + tap/drag disambiguation → Task 6 ✓
- Testing section → unit tests for bucketer (Task 3), interpolator (Task 5), x↔time (Task 6); UI tests for declutter (Task 2) and click-to-seek (Task 6) ✓

**Placeholder scan:** No "TBD"/"handle edge cases"/"write tests for the above" without code. The two soft spots — the SwiftLint ternary note in Task 4 and the UI-test fixture hook in Task 6 — both give a concrete fallback. Acceptable.

**Type consistency:** `WaveformPeakBucketer.bucket(peaks:into:)` used identically in Tasks 3 and 4. `PlayheadInterpolator.renderedTime(observedTime:observedAt:now:rate:duration:)` used identically in Tasks 5 test and `WaveformPlayheadLayer`. `CueMarkersGeometry.time(forX:width:duration:)` used identically in Tasks 6 test and view. `engine.currentTimeObservedAt` defined in Task 5 step 5, consumed in step 6. Accessibility ids referenced in UI tests (`documentShortcutHints`, `importMediaButton`, `documentTitle`, `mediaSummary`, `cueCount`, `waveformSeekSurface`, `playheadOverlay`) match what the views set. Consistent.
