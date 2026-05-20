# Domain Docs

How the engineering skills should consume this repo's domain documentation when exploring the codebase.

## Before exploring, read these

- **`CONTEXT.md`** at the repo root — the project's domain glossary, if it exists.
- **`docs/decisions.md`** — OnlyCue's Architecture Decision Records. This repo keeps **all** ADRs in a single append-only file (newest entry on top), not a `docs/adr/` directory. Read the ADRs that touch the area you're about to work in.

If any of these files don't exist, **proceed silently**. Don't flag their absence; don't suggest creating them upfront. The producer skill (`/grill-with-docs`) creates `CONTEXT.md` lazily when terms or decisions actually get resolved. (`docs/decisions.md` already exists.)

## File structure

Single-context repo:

```
/
├── CLAUDE.md
├── CONTEXT.md            ← domain glossary (created lazily, may not exist yet)
├── docs/
│   ├── decisions.md      ← all ADRs, append-only, newest on top
│   └── agents/           ← this directory
└── OnlyCue/              ← app source
```

## Use the glossary's vocabulary

When your output names a domain concept (in an issue title, a refactor proposal, a hypothesis, a test name), use the term as defined in `CONTEXT.md`. Don't drift to synonyms the glossary explicitly avoids.

If the concept you need isn't in the glossary yet, that's a signal — either you're inventing language the project doesn't use (reconsider) or there's a real gap (note it for `/grill-with-docs`).

## Flag ADR conflicts

If your output contradicts an existing ADR in `docs/decisions.md`, surface it explicitly rather than silently overriding:

> _Contradicts ADR-007 (no App Sandbox entitlements) — but worth reopening because…_

The root `CLAUDE.md` "Hard rules" section mirrors several locked ADRs (ADR-001, ADR-006, ADR-007). Treat those as non-negotiable unless the user explicitly reopens the decision.
