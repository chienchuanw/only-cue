# grandMA2 — hardcode the console credentials, drop the Keychain (#690) — design

**Extends:** #683 / #686 / #688. **Status:** approved (brainstormed with owner).

## Problem

Settings ▸ grandMA2 asks for a **Username** and a **Password** and stores the password in
the macOS Keychain. Both are friction for no benefit: grandMA2 ships a fixed default
`administrator` account (it always exists and cannot be deleted), and the factory password
for it is `admin` — that is what the consoles and onPC we push to use. The user should
never have to type or manage console credentials.

## Design

- **Credentials become constants** on `MA2ConnectionSettings`:
  `username = "administrator"`, `password = "admin"`. The `ma2Username` `@AppStorage` key,
  `defaultUsername`, and `passwordAccount` go away.
- **`MA2SettingsView`** keeps only **Console IP / hostname** (+ the Scan control) and
  **Telnet port**. The Username `TextField`, Password `SecureField`, "Save Password" button
  and its status line are removed, along with `loadPassword` / `savePassword`.
- **`MA2Keychain` is deleted.** The push sheet no longer reads the Keychain; its
  `passwordError` state and the "Could not read the console password…" surface are removed.
  `MA2PushSheet.push()` passes `MA2ConnectionSettings.username` / `.password` straight to
  the runner.
- **Legacy cleanup:** a one-shot `SecItemDelete` for the old generic-password item
  (service `OnlyCue-MA2`, account `grandMA2`) at app start, so a previously-stored secret
  is not abandoned in the user's Keychain. This is the *only* remaining Security-framework
  touch; it is a no-op when nothing was stored.

### Deliberate reversal

# 683's spec required the console password to live in the Keychain and never in
UserDefaults. That requirement existed to protect a **user-entered** secret. With the
credentials hardcoded to a published vendor default there is no user secret, so the
Keychain adds nothing — the requirement is withdrawn here. (No ADR covers it; nothing in
`docs/decisions.md` needs changing.)

### Known trade-off (accepted by the owner)

An operator *can* change the `administrator` password in the console's user management.
Such a console will now fail login with `Login incorrect` and there is no in-app override.
Accepted: our push targets run the factory default. Re-introducing an override later is an
isolated change (one field + one storage decision).

## Components

| Unit | Change |
| --- | --- |
| `MA2ConnectionSettings` | `username`/`password` constants; drop `usernameKey`, `defaultUsername`, `passwordAccount`; delete `MA2Keychain`; add one-shot legacy cleanup |
| `MA2SettingsView` | remove username/password/Save-Password UI + handlers |
| `MA2PushSheet` | drop `@AppStorage username`, the Keychain read, and `passwordError` (state + UI); use the constants |
| `MA2ConnectionSettingsTests` | drop Keychain + username-key tests; assert the new constants |

## Testing

- `MA2ConnectionSettingsTests` — host/port keys and defaults unchanged; **new**: `username == "administrator"`, `password == "admin"`; the Keychain round-trip / account-name tests are deleted with the type.
- Full unit suite + app build + `swiftlint --strict` green. The push path is otherwise untouched (the runner already takes username/password as parameters, so only the call site changes).

## Out of scope

Any override UI for a non-default password (see trade-off), and the `ma2Username`
UserDefaults key left behind by older builds (harmless, no secret).

## Conventions

Conversation zh-TW; code/commits/PRs English. No `Co-Authored-By`. `swiftlint --strict`
clean. macOS ≥ 14.
