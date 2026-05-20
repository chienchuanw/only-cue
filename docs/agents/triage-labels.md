# Triage Labels

The skills speak in terms of five canonical triage roles. This file maps those roles to the actual label strings used in this repo's issue tracker.

| Label in mattpocock/skills | Label in our tracker | Meaning                                  |
| -------------------------- | -------------------- | ---------------------------------------- |
| `needs-triage`             | `needs-triage`       | Maintainer needs to evaluate this issue  |
| `needs-info`               | `needs-info`         | Waiting on reporter for more information |
| `ready-for-agent`          | `ready-for-agent`    | Fully specified, ready for an AFK agent  |
| `ready-for-human`          | `ready-for-human`    | Requires human implementation            |
| `wontfix`                  | `wontfix`            | Will not be actioned                     |

When a skill mentions a role (e.g. "apply the AFK-ready triage label"), use the corresponding label string from this table.

Edit the right-hand column to match whatever vocabulary you actually use.

## Label availability

At setup time, only `wontfix` existed as a GitHub label in this repo. The other four
(`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`) do **not** exist yet.
Create each one the first time the `triage` skill needs it:

```bash
gh label create needs-triage    --color d4a72c --description "Maintainer needs to evaluate"
gh label create needs-info      --color d4a72c --description "Waiting on reporter for more information"
gh label create ready-for-agent --color 0e8a16 --description "Fully specified, ready for an AFK agent"
gh label create ready-for-human --color 0e8a16 --description "Requires human implementation"
```

Note: the repo already has a related yellow label `needs-spec` ("Spec section missing or
unclear"). That is distinct from `needs-info` — `needs-spec` flags a gap in `docs/`, while
`needs-info` waits on the reporter. Keep them separate.
