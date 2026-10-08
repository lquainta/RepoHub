# Repository rulesets

Branch protection for this repository is kept under version control here so changes to it are reviewed like code.

| File | Applies to | Summary |
| --- | --- | --- |
| `protect-main.json` | default branch (`main`) | PR required, squash-only merges, linear history, no force pushes or deletion, review threads must be resolved, automatic Copilot code review, required status checks |

## Required status checks

| Check | Workflow |
| --- | --- |
| `Conventional PR title` | `pr-checks.yml` |
| `Linked issue` | `pr-checks.yml` |
| `SwiftLint` | `lint.yml` |
| `swift-format` | `lint.yml` |
| `Core (macOS)` | `ci.yml` |
| `Core (Linux)` | `ci.yml` |
| `App (macOS)` | `ci.yml` |
| `App UI tests (macOS)` | `ci.yml` |
| `Backend (Linux)` | `ci.yml` |

`integration_id` 15368 is the GitHub Actions app, so only Actions can satisfy these checks.

## Applying a change

After a PR that edits a ruleset is merged, sync it to GitHub:

```sh
# list rulesets to find the id
gh api repos/lquainta/RepoHub/rulesets
# replace the ruleset with the committed definition
gh api -X PUT repos/lquainta/RepoHub/rulesets/<id> --input .github/rulesets/protect-main.json
```

No bypass actors are configured, so repository admins are also subject to these rules.
