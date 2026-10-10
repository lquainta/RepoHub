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

- **UI tests** cover the main user flows end to end. Keep them few and focused. Use launch arguments to point the app at fixture repositories and a stubbed backend, never at the developer's real folders.

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
