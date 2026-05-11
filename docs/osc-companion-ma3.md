# OSC remote control — Companion & grandMA3 reference

OnlyCue runs a **receive-only** OSC server. Enable it in **Settings → OSC**, set a port (default `8000`), and point a controller at this Mac's IP address and that port.

> macOS shows a one-time firewall prompt the first time OnlyCue binds the listen port — click **Allow**.

## Supported address patterns

| Address | Argument | Effect |
|---|---|---|
| `/onlycue/play` | — | Start playback |
| `/onlycue/pause` | — | Pause playback |
| `/onlycue/stop` | — | Pause and rewind to 0 |
| `/onlycue/skip` | int or float `seconds` (signed) | Jump relative to the playhead |
| `/onlycue/locate` | int or float `seconds` | Jump to an absolute time |
| `/onlycue/cue/add` | — | Add a cue at the playhead |
| `/onlycue/cue/next` | — | Move the playhead to the next cue |
| `/onlycue/cue/prev` | — | Move the playhead to the previous cue |

Unrecognised addresses are ignored (they still appear in the future OSC monitor window).

If multiple OnlyCue document windows are open, every message reaches all of them — practically you'll want one document open while driving it over OSC.

## Bitfocus Companion

Use the **Generic: OSC** module (or **Open Sound Control (OSC)** in newer Companion).

1. Add a connection: *Generic OSC*. Set the target IP to this Mac and the target port to your OnlyCue port.
2. On a button, add an action: **Send message without arguments** with OSC Path `/onlycue/play`.
3. For `skip` / `locate`, use **Send message with argument(s)**, OSC Path `/onlycue/skip`, argument type *Integer* (or *Float*), value e.g. `5`.

Example button set for a show-caller deck:

| Button | Action | OSC Path | Argument |
|---|---|---|---|
| GO | Send (no args) | `/onlycue/play` | — |
| HOLD | Send (no args) | `/onlycue/pause` | — |
| TOP | Send (no args) | `/onlycue/stop` | — |
| +5s | Send (1 arg) | `/onlycue/skip` | Integer `5` |
| −5s | Send (1 arg) | `/onlycue/skip` | Integer `-5` |
| NEXT CUE | Send (no args) | `/onlycue/cue/next` | — |
| PREV CUE | Send (no args) | `/onlycue/cue/prev` | — |
| MARK | Send (no args) | `/onlycue/cue/add` | — |

## grandMA3

grandMA3 sends OSC via the `SendOSC` macro line keyword (Setup → Network → OSC must have an output configured pointing at this Mac's IP and OnlyCue port).

Macro lines:

```
SendOSC 1 "/onlycue/play"
SendOSC 1 "/onlycue/pause"
SendOSC 1 "/onlycue/stop"
SendOSC 1 "/onlycue/skip" Int 5
SendOSC 1 "/onlycue/skip" Int -5
SendOSC 1 "/onlycue/locate" Float 30.0
SendOSC 1 "/onlycue/cue/next"
SendOSC 1 "/onlycue/cue/prev"
SendOSC 1 "/onlycue/cue/add"
```

(The leading `1` is the OSC output index configured under Setup → Network → OSC; adjust to match yours.)

Bind these macros to executor buttons or command keys to call OnlyCue from the desk.

## Notes

- v1 is **receive-only** — OnlyCue does not broadcast its transport state back. State-push is part of the Phase-3 console-integration work.
- No Bonjour discovery — configure the IP and port manually.
- See `docs/architecture.md#osc-remote` for the implementation overview and ADR-016 for the design rationale.
