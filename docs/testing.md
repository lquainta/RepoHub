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

Code coverage is collected by `swift test --enable-code-coverage` and the Xcode scheme (`gatherCoverageData`). Reporting and the README badge are set up in #23.
