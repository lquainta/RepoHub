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

3. **Commit** using [Conventional Commits](https://www.conventionalcommits.org/). `make bootstrap` (or `make hooks`) installs git hooks from `.githooks/` that block commits locally when:
   - staged Swift files fail swift-format or SwiftLint
   - Gitleaks finds a secret in the staged changes
   - the message isn't a Conventional Commit

   CI runs the same checks, so `--no-verify` only delays the failure. `scripts/test-git-hooks.sh` proves the hooks block each case.

   Example:

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

## Releases

Versions follow [Semantic Versioning](https://semver.org) and come from the Conventional Commit titles of merged PRs, so nobody picks a version by hand. [release-please](https://github.com/googleapis/release-please) (`.github/workflows/release.yml`) keeps a release PR open, titled `chore: release X.Y.Z`:

- `feat` bumps the minor version, `fix` and `perf` bump the patch, and a `!` or `BREAKING CHANGE:` footer bumps the major (the minor while we're below 1.0).
- The PR updates `CHANGELOG.md`, `version.txt`, `MARKETING_VERSION` in `App/project.yml`, and `RepoHubCore.version`. Lines it edits are marked `x-release-please-version`.
- **Merging it** tags the merge commit `vX.Y.Z` and publishes a GitHub Release with the changelog entry as its notes.
- The app's build number (`CFBundleVersion`) is the commit count, set by `make build-app`.

Release PRs don't need a linked issue. Like any PR, they need green checks.

## Logging

Logs must help diagnose problems without leaking anything private.

| Level | Use for | Example |
| --- | --- | --- |
| `debug` | Detail for developers, off in production | cache key computed, git command arguments |
| `info` | Normal events worth seeing | signed in, scanned 12 repositories, background fetch |
| `notice` | Notable but expected events (backend production default) | migrations ran, configuration loaded |
| `warning` | Something degraded but recovered | Redis unavailable (falling back), webhook signature rejected |
| `error` | An operation failed | git status failed, GitHub returned 502 |
| `critical` / `fault` | The process can't continue | data store can't be opened |

- **Never log secrets.** No tokens, refresh tokens, webhook secrets, or `DATABASE_URL`. Log an identifier (user login, device id) instead.
- **Backend:**
  - log through `req.logger` or `app.contextLogger`, so every line has the request's `request_id`
  - production logs are JSON (`LOG_FORMAT`); the level comes from `LOG_LEVEL` without a code change
  - put structured details in `metadata:`, not the message
- **App:**
  - use `os.Logger` with the `com.lquainta.RepoHub` subsystem and a category per feature
  - mark anything that can identify the user, such as file paths, remote URLs, or git's stderr, as `privacy: .private`
  - `.public` is only for fixed strings and counts

## Architecture decisions

Significant decisions (a new service, library, data store, or a change to how components talk) get an [Architecture Decision Record](docs/adr/README.md) in the same PR. Copy [`docs/adr/template.md`](docs/adr/template.md); never rewrite an accepted ADR. Supersede it with a new one instead.
- the PR is squash-merged and the issue is closed

## Reporting bugs and requesting features

Use the issue templates. Blank issues are disabled.
