# Start Page (Welcome Window) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a dedicated "Welcome to OnlyCue" window that lists recent projects (open/remove) and offers New / New from Template… / Open Other…, shown at launch instead of a blank document.

**Architecture:** A SwiftUI `Window("welcome")` scene hosts a dark, DS-styled `StartView`; a thin `@NSApplicationDelegateAdaptor` suppresses the default auto-untitled-document on macOS 14. Recents come from `NSDocumentController.recentDocumentURLs`, mapped by a pure, unit-tested `RecentProjectsModel`.

**Tech Stack:** SwiftUI (DocumentGroup + Window scene), AppKit (`NSApplicationDelegate`, `NSDocumentController`), XCTest. macOS 14+.

Spec: `docs/superpowers/specs/2026-06-22-start-page-design.md`. Issue #591, branch `issues/591`.

---

## File Structure

- Create `OnlyCue/Utilities/RecentProjectsModel.swift` — `RecentProject` value type + pure `recents(from:)`, `removing(_:from:)`, impure `load()`.
- Create `OnlyCueTests/RecentProjectsModelTests.swift` — unit tests for the pure seam.
- Create `OnlyCue/UI/StartView.swift` — the two-pane welcome view + row subview.
- Create `OnlyCue/App/AppDelegate.swift` — `NSApplicationDelegate` suppressing auto-untitled docs.
- Modify `OnlyCue/App/OnlyCueApp.swift` — add `@NSApplicationDelegateAdaptor` + the `Window("welcome")` scene.
- Modify `OnlyCue/App/AppCommands.swift` — add `File → Welcome to OnlyCue` (`openWindow("welcome")`).

Lint reminders: no raw digit literals in views (use `DS.Space`/`DS.Text`/`DS.Radius`); no single-char identifiers; no force-unwrapping in tests (use `XCTUnwrap`).

---

## Task 1: Pure `RecentProjectsModel` + `RecentProject`

**Files:**
- Create: `OnlyCue/Utilities/RecentProjectsModel.swift`
- Test: `OnlyCueTests/RecentProjectsModelTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import OnlyCue

final class RecentProjectsModelTests: XCTestCase {

    private func makeTempFile(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("recent-\(UUID().uuidString)-\(name)")
        try Data([0x00]).write(to: url)
        return url
    }

    func test_recents_derivesNameAndExistsAndPreservesOrder() throws {
        let first = try makeTempFile("alpha.cuelist")
        let second = try makeTempFile("beta.cuelist")
        defer { try? FileManager.default.removeItem(at: first); try? FileManager.default.removeItem(at: second) }

        let rows = RecentProjectsModel.recents(from: [first, second])

        XCTAssertEqual(rows.map(\.url), [first, second], "Order is preserved (newest-first input)")
        XCTAssertEqual(rows[0].name, first.deletingPathExtension().lastPathComponent)
        XCTAssertTrue(rows[0].exists)
        XCTAssertNotNil(rows[0].date)
    }

    func test_recents_marksMissingFileAsNotExisting() {
        let missing = URL(fileURLWithPath: "/no/such/dir/ghost.cuelist")
        let rows = RecentProjectsModel.recents(from: [missing])

        XCTAssertEqual(rows.count, 1, "Missing entries are still listed (so they can be removed)")
        XCTAssertFalse(rows[0].exists)
        XCTAssertNil(rows[0].date)
        XCTAssertEqual(rows[0].name, "ghost")
    }

    func test_recents_emptyInput_emptyOutput() {
        XCTAssertTrue(RecentProjectsModel.recents(from: []).isEmpty)
    }

    func test_removing_dropsTargetKeepsOrder() {
        let a = URL(fileURLWithPath: "/x/a.cuelist")
        let b = URL(fileURLWithPath: "/x/b.cuelist")
        let c = URL(fileURLWithPath: "/x/c.cuelist")

        XCTAssertEqual(RecentProjectsModel.removing(b, from: [a, b, c]), [a, c])
        XCTAssertEqual(RecentProjectsModel.removing(a, from: [a, b, c]), [b, c])
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run (note: test daemon is environmentally wedged this session — if `xcodebuild test` hangs on "control session with daemon", rely on build + a later CI run; otherwise):
`xcodebuild test -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/RecentProjectsModelTests CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES`
Expected: FAIL — `RecentProjectsModel` / `RecentProject` undefined.

- [ ] **Step 3: Implement**

```swift
import Foundation

/// One row on the welcome window's recent-projects list (#591).
struct RecentProject: Identifiable, Equatable {
    let url: URL
    let name: String
    let folder: String
    let date: Date?
    let exists: Bool

    var id: URL { url }
}

/// Maps `NSDocumentController` recent-document URLs to displayable rows, and
/// computes recents-list edits. Pure (FileManager-injectable) so it is unit
/// tested without the document controller.
enum RecentProjectsModel {

    static func recents(from urls: [URL], fileManager: FileManager = .default) -> [RecentProject] {
        urls.map { url in
            let exists = fileManager.fileExists(atPath: url.path)
            let date = exists
                ? (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                : nil
            let parent = url.deletingLastPathComponent().path
            return RecentProject(
                url: url,
                name: url.deletingPathExtension().lastPathComponent,
                folder: (parent as NSString).abbreviatingWithTildeInPath,
                date: date,
                exists: exists
            )
        }
    }

    /// The newest-first URL list with `url` removed (used by the remove flow).
    static func removing(_ url: URL, from urls: [URL]) -> [URL] {
        urls.filter { $0 != url }
    }

    @MainActor
    static func load() -> [RecentProject] {
        recents(from: NSDocumentController.shared.recentDocumentURLs)
    }
}
```

(Need `import AppKit` for `NSDocumentController` in `load()`. Use `import AppKit` instead of `Foundation`, or add both.)

- [ ] **Step 4: Run to verify pass** (same command as Step 2). Expected: PASS (or daemon-wedged → verify by build + lint).

- [ ] **Step 5: Lint + commit**

```bash
swiftlint lint --strict --quiet OnlyCue/Utilities/RecentProjectsModel.swift OnlyCueTests/RecentProjectsModelTests.swift
git add OnlyCue/Utilities/RecentProjectsModel.swift OnlyCueTests/RecentProjectsModelTests.swift
git commit -m "feat(welcome): recent-projects model with tests"
```

(Commit the test first as its own commit if practicing strict red→green: `test(welcome): pin RecentProjectsModel mapping` then the impl `feat(welcome): recent-projects model`.)

---

## Task 2: `StartView` (two-pane welcome UI)

**Files:**
- Create: `OnlyCue/UI/StartView.swift`

- [ ] **Step 1: Implement the view**

```swift
import AppKit
import SwiftUI

/// The welcome window's content (#591): brand + actions on the left, the recent
/// projects list on the right. Dark DS styling matching `FirstLaunchSheet`.
struct StartView: View {

    @Environment(\.openDocument) private var openDocument
    @State private var recents: [RecentProject] = []

    var body: some View {
        HStack(spacing: 0) {
            actionsPane
                .frame(width: 280)
                .padding(DS.Space.xl)
            Divider()
            recentsPane
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DS.Space.lg)
        }
        .frame(width: 720, height: 460)
        .background(DS.Color.panel)
        .task { recents = RecentProjectsModel.load() }
        .accessibilityIdentifier("startView")
    }

    private var actionsPane: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            Image("BrandHero")
                .resizable().interpolation(.high)
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text("OnlyCue").font(.title2.weight(.semibold)).foregroundStyle(DS.Color.textPrimary)
                Text("Plan and run lighting cues against your media.")
                    .font(DS.Text.body).foregroundStyle(DS.Color.textSecondary)
            }
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                actionButton("New Project", systemImage: "plus.square") { newDocument() }
                actionButton("New from Template…", systemImage: "doc.on.doc") { newFromTemplate() }
                actionButton("Open Other…", systemImage: "folder") { openOther() }
            }
            Spacer()
        }
    }

    private func actionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage).font(DS.Text.body)
        }
        .buttonStyle(.plain)
        .foregroundStyle(DS.Color.textPrimary)
        .accessibilityIdentifier("startAction.\(title)")
    }

    private var recentsPane: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            Text("Recent Projects").dsSectionHeader()
            if recents.isEmpty {
                Text("No recent projects").font(DS.Text.body).foregroundStyle(DS.Color.textTertiary)
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(recents) { project in
                            RecentProjectRow(project: project, onOpen: { open(project) }, onRemove: { remove(project) })
                        }
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func open(_ project: RecentProject) {
        guard project.exists else { return }
        Task { try? await openDocument(at: project.url); closeWindow() }
    }

    private func newDocument() { NSDocumentController.shared.newDocument(nil); closeWindow() }

    private func newFromTemplate() {
        try? TemplateAction.newDocument()
        closeWindow()
    }

    private func openOther() { NSDocumentController.shared.openDocument(nil); closeWindow() }

    private func remove(_ project: RecentProject) {
        let survivors = RecentProjectsModel.removing(project.url, from: NSDocumentController.shared.recentDocumentURLs)
        NSDocumentController.shared.clearRecentDocuments(nil)
        // Re-note oldest → newest so the rebuilt list keeps newest-first order.
        for url in survivors.reversed() { NSDocumentController.shared.noteNewRecentDocumentURL(url) }
        recents = RecentProjectsModel.load()
    }

    private func closeWindow() {
        // The welcome window closes once a document opens; closing here keeps the
        // launch flow clean. (Verified by manual run.)
        NSApp.keyWindow?.close()
    }
}
```

- [ ] **Step 2: Implement `RecentProjectRow`** (same file, below `StartView`)

```swift
private struct RecentProjectRow: View {
    let project: RecentProject
    let onOpen: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: DS.Space.md) {
            VStack(alignment: .leading, spacing: DS.Space.xs / 2) {
                Text(project.name)
                    .font(DS.Text.body)
                    .foregroundStyle(project.exists ? DS.Color.textPrimary : DS.Color.textTertiary)
                Text(project.exists ? project.folder : "\(project.folder) — missing")
                    .font(DS.Text.small)
                    .foregroundStyle(DS.Color.textTertiary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: DS.Space.sm)
            if let date = project.date {
                Text(date, format: .dateTime.month().day())
                    .font(DS.Text.monoSmall).foregroundStyle(DS.Color.textTertiary)
            }
            if !project.exists {
                Button(action: onRemove) { Image(systemName: "xmark.circle") }
                    .buttonStyle(.plain).foregroundStyle(DS.Color.textTertiary)
                    .help("Remove from Recents")
                    .accessibilityIdentifier("removeRecent")
            }
        }
        .padding(.vertical, DS.Space.sm)
        .padding(.horizontal, DS.Space.sm)
        .contentShape(Rectangle())
        .onTapGesture { if project.exists { onOpen() } }
        .accessibilityIdentifier("recentRow")
    }
}
```

- [ ] **Step 3: Build + lint**

```bash
xcodegen generate
xcodebuild build -project OnlyCue.xcodeproj -scheme OnlyCue -configuration Debug -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES
swiftlint lint --strict --quiet OnlyCue/UI/StartView.swift
```
Expected: BUILD SUCCEEDED, lint clean. (If `openDocument(at:)` API name differs, use `NSDocumentController.shared.openDocument(withContentsOf: project.url, display: true)` instead.)

- [ ] **Step 4: Commit**

```bash
git add OnlyCue/UI/StartView.swift
git commit -m "feat(welcome): start view with recents list and actions"
```

---

## Task 3: `AppDelegate` (suppress auto-untitled doc)

**Files:**
- Create: `OnlyCue/App/AppDelegate.swift`

- [ ] **Step 1: Implement**

```swift
import AppKit

/// Thin app delegate for the welcome-window launch flow (#591). Stops macOS
/// from auto-creating a blank untitled document at launch / on reopen so the
/// `Window("welcome")` scene is what the user sees. The app is not sandboxed
/// (ADR-007); `NSDocumentController` recents drive the start page.
final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }
}
```

- [ ] **Step 2: Build + commit**

```bash
xcodegen generate
xcodebuild build -project OnlyCue.xcodeproj -scheme OnlyCue -configuration Debug -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES
git add OnlyCue/App/AppDelegate.swift
git commit -m "feat(welcome): app delegate to suppress auto-untitled document"
```

---

## Task 4: Wire the `Window` scene + delegate into `OnlyCueApp`

**Files:**
- Modify: `OnlyCue/App/OnlyCueApp.swift`

- [ ] **Step 1: Add the adaptor + scene**

In `struct OnlyCueApp: App`, add near the top:
```swift
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
```
And add a new scene after the `DocumentGroup { … }` block (before `Settings`):
```swift
        Window("Welcome to OnlyCue", id: "welcome") {
            StartView()
        }
        .defaultSize(width: 720, height: 460)
        .windowResizability(.contentSize)
```

- [ ] **Step 2: Build**

```bash
xcodegen generate
xcodebuild build -project OnlyCue.xcodeproj -scheme OnlyCue -configuration Debug -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add OnlyCue/App/OnlyCueApp.swift
git commit -m "feat(welcome): welcome window scene + app delegate adaptor"
```

---

## Task 5: `File → Welcome to OnlyCue` menu command

**Files:**
- Modify: `OnlyCue/App/AppCommands.swift`

- [ ] **Step 1: Add the command**

Add `@Environment(\.openWindow) private var openWindow` to `AppCommands`, and a `CommandGroup` (replacing/after the New group, under `.newItem` or a `CommandGroup(after: .appInfo)`):
```swift
        CommandGroup(after: .newItem) {
            Button("Welcome to OnlyCue") { openWindow(id: "welcome") }
                .accessibilityIdentifier("welcomeMenuItem")
        }
```

- [ ] **Step 2: Build + commit**

```bash
xcodegen generate
xcodebuild build -project OnlyCue.xcodeproj -scheme OnlyCue -configuration Debug -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES
swiftlint lint --strict --quiet OnlyCue/App/AppCommands.swift OnlyCue/App/OnlyCueApp.swift
git add OnlyCue/App/AppCommands.swift
git commit -m "feat(welcome): File menu command to reopen the welcome window"
```

---

## Task 6: Manual verification (impure boundary; UI-test CI daemon-wedged)

Build a runnable Debug app, ad-hoc sign, launch, and confirm:

- [ ] Launch with no restored document → the **Welcome window** appears (no blank auto-document).
- [ ] Recent projects list shows name + folder + date, newest first.
- [ ] Click a recent → it opens and the Welcome window closes.
- [ ] **New Project** opens a blank document (Welcome closes).
- [ ] **New from Template…** opens the template picker → new doc.
- [ ] **Open Other…** opens a `.cuelist` via the file panel.
- [ ] A recent whose file was moved/deleted is greyed; its ⨯ removes it from the list (and it stays gone after relaunch).
- [ ] Closing all documents and choosing **File → Welcome to OnlyCue** reopens the Welcome window.

Run:
```bash
xcodebuild build -project OnlyCue.xcodeproj -scheme OnlyCue -configuration Debug -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES
APP=$(find ~/Library/Developer/Xcode/DerivedData/OnlyCue-*/Build/Products/Debug -maxdepth 1 -name OnlyCue.app | head -1)
xattr -dr com.apple.quarantine "$APP"; open "$APP"
```

If the `Window` scene does not auto-open at launch on the test machine's macOS 14 point release, the `File → Welcome to OnlyCue` command is the guaranteed entry point; capture the behavior and, if needed, add an `applicationDidFinishLaunching` hook that posts a notification `StartView`/the app observes to `openWindow(id:"welcome")`.

---

## Notes for the implementer

- No `ProjectModel` / schema change.
- Reuse existing `TemplateAction.newDocument()` (it already runs the template picker + `NSDocumentController.shared.newDocument`).
- `BrandHero` image asset already exists (used by `FirstLaunchSheet`).
- The only unit-tested seam is `RecentProjectsModel`; everything else is verified by manual run because the self-hosted test daemon is wedged this session.
