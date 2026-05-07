---
name: Bug
about: A defect to fix
title: "fix: <short summary>"
labels: ["bug"]
---

## Spec source
Implements: `docs/<file>.md#<anchor>` (the spec section the bug violates)

## Reproduction
1. …
2. …

## Expected
…

## Actual
…

## Environment
- macOS version:
- App version / commit:

## Acceptance criteria (BDD — Gherkin)
```gherkin
Scenario: <regression test for the bug>
  Given …
  When …
  Then …
```

## Definition of Done
- [ ] Failing regression test written first
- [ ] Test passes after fix
- [ ] Spec updated if the bug revealed a spec gap
- [ ] CI green
