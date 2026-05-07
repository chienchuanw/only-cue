## Summary

{One or two sentences describing the performance optimization.}

Closes #{issue_number}

## Baseline Metrics

{What was measured before the optimization, with specific numbers.}

- **Metric**: {what was measured}
- **Before**: {value with units}
- **Measurement method**: {how it was captured}

## Optimization

{Describe the optimization approach and why it works.}

## Changes

- {File or module changed and what was done}
- {New indexes, queries, caching layers, etc.}

## Benchmark Results

{Show the improvement with specific numbers.}

- **After**: {value with units}
- **Improvement**: {percentage or absolute improvement}

## Test Plan

- [ ] Benchmark confirms improvement meets target
- [ ] No regressions in correctness (existing tests pass)
- [ ] {Specific scenario to load test}
- [ ] {Verify no degradation in related operations}

---
## OnlyCue verification (required)
**Spec link:** `docs/<file>.md#<anchor>`
**Closes:** #__   (also updates parent Epic task list)

- [ ] New tests added for every behavior (TDD: red→green committed)
- [ ] Gherkin scenarios from the issue mapped to UI tests where applicable
- [ ] Spec updated if behavior diverged from `docs/`
- [ ] CI green
