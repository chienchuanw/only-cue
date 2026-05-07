---
name: Epic
about: A build-sequence step containing multiple leaf issues
title: "epic: <step name> — <one-line summary>"
labels: ["epic"]
---

## Spec source
Build-sequence step N — `docs/build-sequence.md#step-N`

## Done when
<the acceptance bullet from build-sequence.md>

## Leaves (expand JIT when milestone becomes active)
- [ ] Leaf: <title>
- [ ] Leaf: <title>

## Acceptance (epic-level Gherkin)
```gherkin
Scenario: <name>
  Given …
  When …
  Then …
```

## Out of scope
- …
