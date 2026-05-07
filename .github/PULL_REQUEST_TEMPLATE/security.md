## Summary

{One or two sentences describing the security fix. Do not include exploit details in the PR title.}

Closes #{issue_number}

## Vulnerability Addressed

{Describe the vulnerability type and its impact without providing weaponized details.}

- **Type**: {SQL injection, XSS, CSRF, etc.}
- **Severity**: {Critical / High / Medium / Low}
- **Impact**: {What could an attacker achieve}

## Fix Approach

{Describe how the vulnerability was fixed and why this approach was chosen. Reference security best practices.}

## Changes

- {File or module changed and what was done}
- {New validation, sanitization, or access controls added}

## Verification Steps

- [ ] Vulnerability is no longer reproducible
- [ ] Fix does not introduce new security issues
- [ ] {Specific security control verified}
- [ ] {Input validation test case}

## Security Checklist

- [ ] No secrets or credentials in the diff
- [ ] Dependencies are up to date (if relevant)
- [ ] Error messages do not leak internal details
- [ ] Security test added to prevent regression

---
## OnlyCue verification (required)
**Spec link:** `docs/<file>.md#<anchor>`
**Closes:** #__   (also updates parent Epic task list)

- [ ] New tests added for every behavior (TDD: red→green committed)
- [ ] Gherkin scenarios from the issue mapped to UI tests where applicable
- [ ] Spec updated if behavior diverged from `docs/`
- [ ] CI green
