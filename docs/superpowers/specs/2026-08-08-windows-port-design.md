# OnlyCue on Windows — design

**Status:** approved (grill/brainstorm 2026-08-08, conducted in zh-Hant)
**Spec section implemented:** this file is the spec; implementing PRs link back here.

## Problem & motivation

OnlyCue is a native macOS app (~26k LOC Swift, 289 files) with no cross-platform
abstraction: SwiftUI in 123 files, Foundation in 142, AppKit in 36, AVFoundation
in 19, plus CoreAudio, CoreMIDI, Quartz, Security. SwiftUI / AppKit /
AVFoundation / CoreAudio / CoreMIDI **do not exist on Windows** — the Swift
toolchain runs on Windows but Apple's frameworks do not.

Two drivers: **(A)** grow into the Windows live-events / lighting market, and
**(B)** a specific client/venue runs Windows. **No hard deadline — ship
incrementally, do it right.**

## Approach (the decisions)

The absence of a mature native Swift GUI on Windows rules out "recompile the Swift
app." The agreed architecture:

1. **Do not touch macOS.** Swift/SwiftUI stays first-class, unchanged.
2. **Windows UI = WinUI 3 + C#/.NET** — the most first-class Windows stack for
   native feel, WASAPI/WinRT-MIDI/sockets, and MSIX packaging.
3. **Core-sharing mechanism = re-implement the core in C#, share the contract, not
   the compiled code.** The shared artifacts are the `.cuelist` **JSON schema**,
   the **behavioural spec**, and **golden test vectors**. macOS produces the
   golden vectors; Windows CI verifies C# output byte-for-byte against them. This
   was chosen over a single shared Swift core behind a C ABI because the natural
   sharing boundary is language-neutral data (`.cuelist` JSON, MA2/OSC command
   strings, timecode math), and Swift-for-Windows tooling is too immature to carry
   a production core across FFI. Cost accepted: core logic is maintained twice;
   drift is contained by the golden-vector gate.
4. **Platform-specific layers re-implemented on Windows:** transport (sockets),
   media engine, audio LTC (WASAPI/ASIO), MIDI (WinRT).

### What is shareable vs platform-specific (from the audit)

Cross-platform pure logic (mostly `import Foundation` only — re-implemented in C#,
locked by golden vectors):
- `Document` (ProjectModel, schema v19, migrations) → shared `.cuelist` JSON schema.
- `Commands` (the CueCommands mutation семья) → behavioural spec + vectors.
- MA2 / OSC **command-planning** logic (the string/byte output) → golden vectors.
- `Tempo` / beat-grid math → golden vectors.

Platform-specific, must be re-written on Windows:
- Transport: `Network.framework` → Windows sockets (MA2 telnet, OSC are just TCP/UDP).
- Media + waveform: `AVFoundation` → Windows media engine (M2 decision).
- Audio LTC: `CoreAudio` / `MediaToolbox` → WASAPI/ASIO (M3).
- MIDI: `CoreMIDI` → WinRT MIDI (M3).
- Security-scoped bookmarks (ADR-006) have no Windows equivalent — see Product.

## UI (design-first, and fully up front)

5. **Unified brand visual (high visual consistency).** Both platforms look as
   alike as possible; WinUI is the technical substrate wearing an OnlyCue brand
   theme, **not** the default Fluent look. WinUI is still fully used as the
   framework — only its default theme is replaced.
6. **Both platforms are dark-only** (Windows inherits the spirit of ADR-029; a
   parallel cross-platform ADR will be written).
7. **Fonts:** macOS keeps SF Pro; Windows embeds **Inter** (a high-fidelity SF
   approximation) so nothing on macOS changes.
8. **Figma:** the existing "OnlyCue Design System" file
   (`NhH2957iKQ8b581x3gI3Wk`), add pages — `Foundations` (shared tokens),
   `macOS Screens`, `Windows Screens` — one shared component library, platform
   differences as variants (window chrome, menu bar, context menus, file dialogs).
9. **Production split:** the agent produces the **complete** two-platform UI (all
   milestones' screens) via the Figma MCP; the maintainer reviews/finalizes.
   **Design is finalized before any Windows code is written.**

## Product

10. **`.cuelist` is fully cross-platform.** Portable paths are the primary media
    reference; the security-scoped bookmark becomes a macOS-only optimization that
    Windows ignores (path fallback). Cross-machine missing media uses the existing
    relink flow. A single `.cuelist` opening on both Mac and PC is a headline
    differentiator for mixed Mac/PC production teams (driver A).

## Repository

11. **Monorepo.** The Windows C# solution lives in the same repo (e.g. a
    `windows/` subtree) alongside the `.cuelist` schema, golden test vectors,
    docs, and Figma references — one source of truth, so cross-platform changes
    cannot silently drift. The Swift (xcodegen) and .NET builds stay independent.

## Constraints / risks

12. **Maintainer is not fluent in C#/.NET/WinUI.** The agent leads the Windows
    side: solution scaffold, examples, the golden-vector bridge, and CI; the
    maintainer reviews. This raises the agent's hand-holding burden and is an
    explicit project risk.
- **Drift risk** between the two core implementations — mitigated by the
  golden-vector gate (macOS-generated vectors, Windows CI verifies).
- **Swift-for-Windows was rejected**, so no shared compiled core; the重複 tax is
  the accepted trade.
- **Audio/timecode fidelity on Windows** (WASAPI/ASIO latency, frame-accuracy) is
  the highest-risk technical area — deliberately deferred to M3.

## Milestones (implement per-milestone after the full Figma is finalized)

- **M0 — Windows foundation:** C#/.NET solution scaffold, the golden-test-vector
  export (from macOS) + verification mechanism, Windows CI (GitHub Actions
  windows runner), the shared `.cuelist` schema as the contract.
- **M1 — planning + MA2 (shared logic + sockets, no audio hardware):** `.cuelist`
  read/write + migrations, cue list/grid/inspector planning UI, tempo/beat grid,
  MA2 telnet timecode push, MA2 plugin (lua/xml) export, OSC. A usable
  "plan cues + push to grandMA2" Windows build.
- **M2 — media:** video/audio preview playback + waveform + timecode alignment
  (Windows media-engine selection — Media Foundation vs libVLC vs WinRT — is an
  open decision for M2).
- **M3 — hardware timecode / MIDI:** LTC audio output (WASAPI/ASIO), MIDI in/out.
- **M4 — polish:** Windows update mechanism, MSIX packaging + signing, i18n
  (map the String Catalog to .NET resources, including the shipped zh-Hant).

## Execution order

1. **UI first (complete):** agent produces the full two-platform UI in Figma →
   maintainer finalizes. Requires authenticating Figma in-session
   (`/mcp` → figma → Authenticate, `frankwang16@gmail.com`).
2. **M0** Windows foundation (scaffold + golden-vector bridge + CI).
3. **M1 → M4** per-milestone.

## ADRs to write

- Windows dark-only (parallel to ADR-029).
- No sandbox / no security-scoped bookmarks on Windows; portable-path media refs
  (relates to ADR-006, ADR-007).
- C#-reimplemented core + golden-vector contract (the core-sharing decision).
- Inter as the Windows brand font.

## Verification strategy

- **Golden vectors** are the cross-platform correctness gate: macOS emits vectors
  for `.cuelist` round-trips, MA2/OSC command output, cue-numbering rules, and
  timecode math; Windows CI asserts the C# core reproduces them exactly.
- Windows UI gets its own test layer (WinUI UI tests) per milestone.
- The existing macOS test suite is untouched.
