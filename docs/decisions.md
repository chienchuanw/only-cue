# Architecture Decision Records

Append-only log of locked decisions. Newer entries on top. Each ADR captures **what**, **why**, and **what it costs to reverse**.

ADR template:

```markdown
## ADR-NNN — Title
**Date**: YYYY-MM-DD
**Status**: Accepted | Superseded by ADR-MMM
**Decision**: One sentence.
**Why**: 2–4 sentences.
**Reversal cost**: How painful would changing this be?
```

---

## ADR-007 — Sandbox off for MVP, ship via Developer ID DMG
**Date**: 2026-05-07
**Status**: Accepted
**Decision**: Distribute as a Developer ID-signed, notarized DMG. App Sandbox is **off**.
**Why**: The target audience is pro users who expect full filesystem access, virtual audio drivers, and console integrations. App Store sandbox would block features we want in phase 2 (LTC routing, OSC). DMG is the standard distribution form for tools in this space.
**Reversal cost**: Medium. Adopting sandbox later requires auditing every file/network access and adding entitlements. No code rewrite, but a careful audit.

## ADR-006 — JSON `.cuelist` document with referenced media
**Date**: 2026-05-07
**Status**: Accepted
**Decision**: Project files are pretty-printed JSON. Media is referenced via security-scoped bookmarks, not embedded.
**Why**: JSON diffs cleanly, is inspectable, and trivial to migrate. Embedding media would bloat files and complicate templates. Bookmarks survive moves within a volume and get a clean error path when they don't.
**Reversal cost**: Low for JSON-internal changes (versioned migrations). Medium if we ever want a self-contained bundle — we'd add a `.cuelistx` package format alongside, not replace the JSON.

## ADR-005 — Both audio and video supported from day 1
**Date**: 2026-05-07
**Status**: Accepted
**Decision**: MVP supports `.mp3 .wav .aac .m4a .aiff` and `.mp4 .mov`.
**Why**: `AVPlayer` handles both behind one API. The marginal cost of adding video is one `NSViewRepresentable` wrapping `AVPlayerLayer`. Punting video would force the audience to wait for v2 just to plan TV broadcasts, which is half their work.
**Reversal cost**: N/A — adding more types later is trivial.

## ADR-004 — Lighting designers as the primary audience for v1
**Date**: 2026-05-07
**Status**: Accepted
**Decision**: Optimize the v1 workflow for lighting designers and show programmers, mirroring CuePoints.
**Why**: The reference product validates the workflow for this audience. A focused first release is easier to evaluate and easier to market. Broader audiences (podcasters, theater stage managers) can be reached later by extending — not redesigning.
**Reversal cost**: Low if we keep the cue model generic (we do). High if we hard-code lighting-specific UI strings or workflows; we won't.

## ADR-003 — MVP is a thin slice; LTC and exports defer to phase 2
**Date**: 2026-05-07
**Status**: Accepted
**Decision**: v1 ships the core loop only: import → mark → save → reopen.
**Why**: LTC, templates, exports, and shortcut customization are valuable but uncorrelated risks. Shipping the core loop first proves the document model, the player, and the cue UX before we layer protocols on top.
**Reversal cost**: Low — phase 2 features are designed as additive seams.

## ADR-002 — MVVM with `@Observable` view models, document-based app
**Date**: 2026-05-07
**Status**: Accepted
**Decision**: One `CueListDocument` per file via `DocumentGroup` + `ReferenceFileDocument`. View models use Swift's `@Observable` macro. UI never mutates the model directly — all mutations go through `CueCommands`.
**Why**: `DocumentGroup` gives us new/open/save/recents/autosave for free. Routing mutations through commands gives us undo correctness in one place and a future seam for collaboration, telemetry, and AI-suggested cues.
**Reversal cost**: High once views are written. Worth getting right early.

## ADR-001 — Native Swift + SwiftUI + AVFoundation; macOS 14+
**Date**: 2026-05-07
**Status**: Accepted
**Decision**: Build natively in Swift with SwiftUI for UI and AVFoundation for media. Minimum target is macOS 14 (Sonoma).
**Why**: Media performance and timecode-grade timing are the core of the product, and AVFoundation gives us frame-accurate seeking, hardware-accelerated decode, and a battle-tested player. Cross-platform stacks (Electron, Tauri, Flutter) all add a media-handling layer we'd have to maintain. Targeting macOS 14 unlocks `@Observable`, `inspector`, and modern `ScrollView` APIs we'll lean on.
**Reversal cost**: Total. Switching stacks means rewriting the app. We accept this lock-in.
