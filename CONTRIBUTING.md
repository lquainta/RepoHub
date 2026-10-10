# Contributing to RepoHub

This project follows a strict issue → branch → pull request workflow so every change on `main` can be traced back to the reason it was made.

## Workflow

1. **Start from an issue.** Every change, including chores and docs, needs an issue. Create one from a template if it does not exist. Make sure it has a type label, an area label, and a milestone.
2. **Create a branch** from an up-to-date `main`:

   ```text
   <type>/<issue-number>-<short-description>
   ```

   Examples: `feat/67-git-status-parser`, `fix/112-crash-on-empty-folder`, `ci/38-ci-pipeline`.

   | Type | Use for |
   | --- | --- |
   | `feat` | User-facing functionality |
   | `fix` | Bug fixes |
   | `test` | Adding or improving tests |
   | `docs` | Documentation only |
   | `ci` | Workflows, pipelines, deployment |
   | `chore` | Tooling, configuration, dependencies |
   | `refactor` | Code changes that neither fix a bug nor add a feature |
   | `perf` | Performance improvements |

3. **Commit** using [Conventional Commits](https://www.conventionalcommits.org/):

   ```text
   feat(core): parse porcelain v2 branch headers

   Refs #67
   ```

   Scopes: `app`, `core`, `backend`, `ci`, `docs`, `deps`. Keep commits small and focused.

4. **Open a pull request** early (as a draft if it is not ready).
   - The title must be a Conventional Commit, e.g. `feat(core): parse porcelain v2 status`.
   - The body must contain a closing keyword for the issue: `Closes #67`.
   - Fill in the PR template's self-review checklist.
5. **Review.** Copilot code review runs automatically. Every comment must be addressed in a new commit or resolved with a reply explaining why. Merging is blocked until all conversations are resolved.
6. **Merge** with **Squash and merge** (the only allowed method). The squash commit uses the PR title and body, so the commit on `main` looks like:

   ```text
   feat(core): parse porcelain v2 status (#84)

   ...
   Closes #67
   ```

   This links every commit on `main` to both its pull request and its issue. The issue closes automatically and the branch is deleted.

## Branch protection

`main` is protected by the ruleset in [`.github/rulesets/`](.github/rulesets/). Direct pushes, force pushes, and branch deletion are blocked for everyone, including admins. All changes must go through a pull request with passing required checks.

## Definition of done

A change is done when:

- the issue's acceptance criteria are met
- tests cover the new behavior and CI is green
- lint and format checks pass
- documentation, diagrams, ADRs, or the OpenAPI spec are updated if affected

## Architecture decisions

Significant decisions (a new service, library, data store, or a change to how components talk) get an [Architecture Decision Record](docs/adr/README.md) in the same PR. Copy [`docs/adr/template.md`](docs/adr/template.md); never rewrite an accepted ADR. Supersede it with a new one instead.
- the PR is squash-merged and the issue is closed

## Reporting bugs and requesting features

Use the issue templates. Blank issues are disabled.
