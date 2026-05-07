## Summary

{One or two sentences describing what bug this PR fixes and how.}

Closes #{issue_number}

## Root Cause

{Explain what was causing the bug. Reference specific files, functions, and logic paths.}

## Fix Description

{Describe what was changed to fix the bug. Explain why this approach was chosen.}

## Changes

- {File or module changed and what was done}
- {Another change}

## How to Test

- [ ] {Specific steps to verify the fix}
- [ ] {Edge case to check}
- [ ] {Verify no regressions in related functionality}

## Regression Risk

{Describe any areas that could be affected by this change. Write "Low — change is isolated to the bug path" if the risk is minimal.}

---
## OnlyCue verification (required)
**Spec link:** `docs/<file>.md#<anchor>`
**Closes:** #__   (also updates parent Epic task list)

- [ ] New tests added for every behavior (TDD: red→green committed)
- [ ] Gherkin scenarios from the issue mapped to UI tests where applicable
- [ ] Spec updated if behavior diverged from `docs/`
- [ ] CI green
