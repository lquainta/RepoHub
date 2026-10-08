# Code review instructions for RepoHub

RepoHub is a native macOS SwiftUI app (`App/`), a shared Swift package (`Packages/RepoHubCore/`), and a Vapor backend (`Backend/`) using PostgreSQL and Redis. Swift 6 with strict concurrency is used throughout.

When reviewing pull requests, prioritize in this order:

## 1. Correctness
- Logic errors, unhandled edge cases (detached HEAD, no upstream, missing `git` binary, empty folders, network failures).
- Swift concurrency: data races, work on the main actor that should not be, missing `Sendable` conformance, unstructured `Task {}` without cancellation handling.
- Fluent migrations must implement `revert` and must not break existing data.

## 2. Security
- Secrets, tokens, or credentials in code, tests, fixtures, or log statements.
- Configuration must come from environment variables (`Environment.get`), never hard-coded.
- GitHub tokens in the app must be stored in Keychain only.
- Webhook payloads must have their signatures verified; user input must be validated.
- Shell commands built from strings: `git` must be invoked with argument arrays, never through a shell.

## 3. Tests
- New behavior needs tests that would fail without the change. Flag tests that only exercise getters/setters or assert nothing meaningful.
- Parsers in `RepoHubCore` should be tested against fixtures covering edge cases.

## 4. Maintainability
- Force unwraps (`!`), `try!`, and `fatalError` outside tests.
- View logic belongs in view models, not SwiftUI views; dependencies are injected through protocols.
- User-facing strings must be localized (String Catalog), not hard-coded.
- Controls need accessibility labels; status must not be conveyed by color alone.
- Public APIs need doc comments.

## Style
Formatting and lint are enforced by swift-format and SwiftLint in CI; do not comment on issues those tools catch.

Be concise. Group minor nits into a single comment. Do not restate what the code does.
