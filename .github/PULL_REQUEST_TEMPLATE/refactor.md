## Summary

{One or two sentences describing what was refactored and why.}

Closes #{issue_number}

## Motivation

{Why this refactoring is needed now. What pain points does the current code cause.}

## Before / After

{Describe the structural change. What did the code look like before, and what does it look like after.}

## Changes

- {File or module changed and what was done}
- {Files created, moved, or deleted}

## Behavioral Impact

{State explicitly whether this refactoring changes any external behavior. If yes, describe. If no, state: "No behavioral changes — this is a pure structural refactoring."}

## Test Plan

- [ ] All existing tests pass without modification
- [ ] {Specific area to verify manually}
- [ ] {Confirm no regressions in dependent modules}

---
## OnlyCue verification (required)
**Spec link:** `docs/<file>.md#<anchor>`
**Closes:** #__   (also updates parent Epic task list)

- [ ] New tests added for every behavior (TDD: red→green committed)
- [ ] Gherkin scenarios from the issue mapped to UI tests where applicable
- [ ] Spec updated if behavior diverged from `docs/`
- [ ] CI green
