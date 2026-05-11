## Summary

{One or two sentences describing the test coverage this PR adds and what behavior / code path it pins.}

Closes #{issue_number}

## Motivation

{Why this coverage is needed now — a gap surfaced in review, a leaf of the parent epic, a regression that escaped, a refactor that needs a safety net. Reference the spec section or epic.}

## What's Covered

- {Module / function under test and the cases added (happy path, edge cases, error paths)}
- {Gherkin scenarios from the issue mirrored as XCUITests, where applicable}
- {Fixtures / golden files added and what they represent}

## What's NOT Covered (and why)

{Cases deliberately left out — e.g. UI states XCUITest can't easily reach, scenarios owned by a sibling leaf, things that need a fixture not worth building yet. Be explicit so the gap is a known one, not a silent one.}

## How to Verify

- [ ] `xcodebuild test` (or the relevant `-only-testing:` target) — all green
- [ ] `swiftlint --strict` clean
- [ ] {Any non-obvious setup the new tests need}

---
## OnlyCue verification (required — test)
**Spec link:** `docs/<file>.md#<anchor>`
**Closes:** #__   (also updates parent Epic task list)

- [ ] New tests added for the targeted behavior (and they fail without the code under test, where that's meaningful)
- [ ] Gherkin scenarios from the issue mapped to UI tests where applicable (gaps called out above)
- [ ] No production behavior change (or any incidental change is minimal and noted)
- [ ] CI green
