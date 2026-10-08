# Repository rulesets

Branch protection for this repository is kept under version control here so changes to it are reviewed like code.

| File | Applies to | Summary |
| --- | --- | --- |
| `protect-main.json` | default branch (`main`) | PR required, squash-only merges, linear history, no force pushes or deletion, review threads must be resolved, automatic Copilot code review |

Required status checks are added to `protect-main.json` as CI jobs land (see #38).

## Applying a change

After a PR that edits a ruleset is merged, sync it to GitHub:

```sh
# list rulesets to find the id
gh api repos/lquainta/RepoHub/rulesets
# replace the ruleset with the committed definition
gh api -X PUT repos/lquainta/RepoHub/rulesets/<id> --input .github/rulesets/protect-main.json
```

No bypass actors are configured, so repository admins are also subject to these rules.
