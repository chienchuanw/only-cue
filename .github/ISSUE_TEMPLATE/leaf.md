---
name: Leaf
about: A single behavior under an epic, sized for one PR
title: "<feat|fix|test|refactor>: <short summary>"
labels: ["leaf"]
---

## Spec source (SDD)
Implements: `docs/<file>.md#<anchor>`
Related: `<other docs>`

## What
One-paragraph description of the user-visible or internal behavior.

## Acceptance criteria (BDD — Gherkin)
```gherkin
Scenario: <name>
  Given …
  When …
  Then …
```

## Tests to write first (TDD)
- [ ] Unit: `<TestClass>.<test_method>`
- [ ] UI: `<UITestClass>.<test_method>` (covers Scenario X)

## Out of scope
- …

## Definition of Done
- [ ] All tests above written and **failing first** (red), then green
- [ ] Spec section updated if behavior diverged
- [ ] PR linked to this issue and to the parent Epic
- [ ] CI green
