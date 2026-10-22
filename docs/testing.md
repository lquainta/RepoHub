# Testing

RepoHub has three kinds of tests. Every PR must keep all of them green in CI.

| Kind | Framework | Where | Runs with |
| --- | --- | --- | --- |
| Unit | Swift Testing | `Packages/RepoHubCore/Tests`, `App/Tests/RepoHubTests`, `Backend/Tests` | `make test` |
| Integration | Swift Testing | Same targets, tagged `.integration` | `make test` |
| UI / end-to-end | XCTest (XCUITest) | `App/Tests/RepoHubUITests` | `make test-ui` |

`make test` does not run UI tests, because they launch the app and take over the mouse and keyboard. CI runs both.

## What to test

- **Unit tests** cover logic in isolation: parsers, view models, request validation, and mapping. Dependencies are injected through protocols (for example `GitCommandRunning`) and replaced with fakes.
- **Integration tests** exercise real dependencies: the actual `git` binary against temporary repositories, and the backend against real PostgreSQL and Redis. Tag them so they can be filtered:

  ```swift
  @Test(.tags(.integration))
  func fetchUpdatesAheadBehind() async throws { ... }
  ```

- **Backend integration tests** need PostgreSQL. They read `TEST_DATABASE_URL` and are **skipped when it isn't set**, so `make test` works without a database. Each test migrates an empty schema and reverts it afterwards, so the test database must be disposable. Never point it at a development or production database. CI and the DevContainer provide one:

  ```sh
  docker run -d --name repohub-test-db -p 5433:5432 -e POSTGRES_USER=repohub \
    -e POSTGRES_PASSWORD=repohub -e POSTGRES_DB=repohub_test postgres:18.6-alpine
  TEST_DATABASE_URL=postgres://repohub:repohub@localhost:5433/repohub_test make test-backend
  ```

- **Redis integration tests** read `TEST_REDIS_URL` and are skipped without it. They use unique keys and never flush, so the development Redis is fine:

  ```sh
  TEST_REDIS_URL=redis://localhost:6379 make test-backend
  ```

- **Git integration tests** (`RepoHubCore`, tagged `.integration`) run the real `git` binary against temporary repositories created by `TemporaryRepository`. That helper isolates them from your git config (`GIT_CONFIG_GLOBAL=/dev/null`, a fixed identity) and removes them afterwards. They cover:
  - scanning a tree of real repositories: linked worktrees found; submodules and bare repositories skipped
  - status of fresh, committed, and dirty repositories
  - ahead/behind against a bare `origin` after commits on another clone
  - fetch, fast-forward pull, and a diverged pull that must not merge
  - details: branches, commits, remotes, stashes
  - stale-branch detection and safe or forced branch deletion, including on the remote
  - process timeouts and cancellation
- **Performance tests** (`PerformanceTests`, tagged `.performance`) benchmark scanning 500 generated repositories and parsing a 50,000-entry `git status`. They're opt-in, because timings only mean something in a release build:

  ```sh
  make bench   # REPOHUB_BENCHMARK=1 swift test -c release --filter PerformanceTests
  ```

  CI runs them on every PR and writes the results to the job summary. A test **fails if its time budget is exceeded**, so large regressions block merging.

  | Benchmark | Measured (M-series Mac, release) | Budget |
  | --- | --- | --- |
  | Scan 500 repositories, concurrent | 22 ms | **250 ms** |
  | Scan 500 repositories, sequential baseline | 43 ms (concurrency is 1.9× faster) | — |
  | Parse a 50,000-entry status | 94 ms | **500 ms** |

- **App view models** (`App/Tests/RepoHubTests`) never touch the network, the user's Keychain, or their repositories. Every view model takes its dependencies through a protocol, and the tests pass a fake. Shared fakes are in [`Fakes.swift`](../App/Tests/RepoHubTests/Fakes.swift); fakes used by one suite sit next to it:

  | Seam | Real implementation | Fake |
  | --- | --- | --- |
  | `GitServicing` (status, details, fetch/pull, remotes, stale branches) | `GitService` | `FakeGit`: canned results per path, records calls and peak concurrency |
  | `RepositoryScanning` | `RepositoryScanner` | `FakeScanner`: canned folders |
  | `APIClienting` (sign-in, sessions, GitHub status) | `RepoHubAPI` (generated OpenAPI client) | `FakeAPI`: scripted polls and statuses, records batches |
  | `CredentialStoring` | `KeychainCredentialStore` | `InMemoryCredentialStore` |
  | `WorkspaceOpening` (open apps, browser, clipboard) | `SystemWorkspace` | `FakeWorkspace` |
  | `LoginItemManaging` | `SystemLoginItem` (`SMAppService`) | `FakeLoginItem` |
  | `FileWatching` | `FSEventsWatcher` | `FakeWatcher`: emits changes on demand |
  | Persistence (`LibraryStore`) | SwiftData on disk | `Persistence.makeInMemoryContainer()` |
  | Time | `Task.sleep`, `Date.init` | injected `sleep` / `now` closures (`TestClock`) |

  What's covered, by view model: `LibraryViewModel` (scanning, rescans, folders, groups, scope, search and quick filters, selection, Fetch All, GitHub badges), `RepositoryFilter` and `DashboardSort` (search, filters, every sort column), `StatusMonitor` (refresh, bounded concurrency, re-requests, error states), `RepositoryDetailModel` (loading, failures, stale selections), `RepositoryActions` (fetch, pull, open, copy, failures), `StaleBranchModel` (preselection and the force-delete confirmation flow), `AccountModel` (device flow, restore, refresh, sign-out), `GitHubStatusModel`, `SettingsModel`, and `AttentionSummary`. Only the FSEvents watcher tests (`AutoRefreshTests`) use the real file system, in a temporary folder they create and delete.
- **UI tests** cover the main user flows end to end. Keep them few and focused. They run against an in-memory store, fixture repositories, and a stubbed backend, never the developer's real folders, Keychain, or the production API. Environment variables set this up (see `UITestSupport`):

  | Variable | Effect |
  | --- | --- |
  | `REPOHUB_UI_TEST_IN_MEMORY_STORE=1` | Empty in-memory SwiftData store and credential store; no notification prompts or crash reporting |
  | `REPOHUB_UI_TEST_FIXTURE_REPOSITORIES` | Folders with empty `.git` directories, for scanning |
  | `REPOHUB_UI_TEST_GIT_FIXTURES=1` | Real repositories made with `git`: `clean`, `dirty` (an untracked file), and `stale` (a merged `old-feature` branch) |
  | `REPOHUB_UI_TEST_STUB_BACKEND=1` | `UITestBackend`: sign-in shows `TEST-CODE` and is approved at once as `octocat`; no browser is opened |

  `FlowTests` covers adding a folder (repositories listed), filtering by uncommitted changes, opening a repository's details, cleaning up a merged branch, and signing in and out. `LaunchTests` covers the empty state and scanning. On failure, a test attaches the app's accessibility tree to the result bundle. SwiftUI often exposes a row's text as one combined **value** rather than a label, so match with `label CONTAINS … OR value CONTAINS …`.

Don't write tests for trivial getters, setters, or memberwise initializers.

## Conventions

- **Naming**: suites are named after the type under test (`@Suite("PorcelainStatusParser")`). Test names describe behavior: `@Test("Detached HEAD has no branch name")`.
- **Arrange / act / assert**: one behavior per test. Use parameterized tests (`@Test(arguments:)`) for input tables instead of loops.
- **Fixtures**: recorded command output lives in `Tests/<Target>/Fixtures/` and is loaded with `Bundle.module`. Name fixtures after the scenario (`detached-head.txt`).
- **Isolation**: tests must not depend on execution order, the network, or files outside a temporary directory they create and delete.
- **No sleeps**: wait on conditions (`waitForExistence`, `confirmation`) instead of fixed delays.
- **Errors**: use `#expect(throws:)` to assert the specific error, not just that something threw.

## Coverage

```sh
make coverage    # writes coverage/core.lcov, coverage/backend.lcov, coverage/app.lcov and prints totals
```

| Flag | Measured by | Sources counted |
| --- | --- | --- |
| `core` | `RepoHubCore` package tests (`scripts/package-coverage.sh`) | `Packages/RepoHubCore/Sources` |
| `backend` | Backend package tests | `Backend/Sources` (RepoHubCore excluded; it has its own flag) |
| `app` | App unit tests (`scripts/app-coverage.sh`) | `App/Sources` |

Tests, dependencies, and manifests are excluded. CI uploads each report to [Codecov](https://codecov.io/gh/lquainta/RepoHub) with its flag, writes the percentage to the job summary, and Codecov comments on PRs with the coverage diff. `codecov.yml` fails the `codecov/project` status if total coverage drops by more than 2%.
