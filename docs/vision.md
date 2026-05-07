# Vision

## Who

**Lighting designers and show programmers** working on live events, concerts, theater, and TV broadcast. They pre-plan lighting cues against a song or video reference, then drive a lighting console — typically by sending **LTC timecode** that the console chases.

## Problem

Pre-planning cues today happens in a mix of spreadsheets, paper notes, and DAWs. None of these tools are purpose-built for the workflow:

- Spreadsheets can't play media or scrub.
- DAWs play media but treat markers as second-class — no color, no notes, awkward export.
- Console software doesn't help with creative pre-planning before the venue is wired up.

CuePoints validates that a single-purpose **cue planning tool** is wanted by this audience.

## What we're building

A focused, document-based macOS app that does one thing well:

> Open a media file → see/hear it → drop named, color-coded cues at the right moments → save → hand off.

## Why a clone first

We deliberately match CuePoints' core surface for v1 because:

- The workflow is well-validated by the reference product.
- Rebuilding it teaches us the domain (timecode, console handoff, lighting team conventions).
- It keeps decisions cheap — when in doubt, defer to the reference.

A **distinctive feature** comes after the core works. Candidates we may revisit:

- **AI-assisted cueing** — auto-suggest cues from audio transients, beat detection, scene changes, silence boundaries.
- **Collaboration** — multi-user real-time cue list editing.
- **Tighter console integration** — direct OSC/MIDI to common consoles (grandMA, ETC EOS, Hog).

We are explicitly *not* committing to any of these yet. See [`roadmap.md`](roadmap.md).

## Non-goals

- Replacing a DAW. We are not a multi-track editor.
- Replacing a lighting console. We don't render lighting; we only plan timing.
- Mobile or web for v1. Mac native only.
