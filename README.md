# RepoHub

[![CI](https://github.com/lquainta/RepoHub/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/lquainta/RepoHub/actions/workflows/ci.yml)
[![Lint](https://github.com/lquainta/RepoHub/actions/workflows/lint.yml/badge.svg?branch=main)](https://github.com/lquainta/RepoHub/actions/workflows/lint.yml)
[![CodeQL](https://github.com/lquainta/RepoHub/actions/workflows/codeql.yml/badge.svg?branch=main)](https://github.com/lquainta/RepoHub/actions/workflows/codeql.yml)

A native macOS dashboard for all your local git repositories: status, stale branches, pull requests, and CI at a glance.

> 🚧 Under active development. Build and run instructions are coming in [#13](https://github.com/lquainta/RepoHub/issues/13).

## Repository layout

| Path | Contents |
| --- | --- |
| `App/` | macOS SwiftUI application |
| `Packages/RepoHubCore/` | Shared Swift package (models, git parsing) used by the app and backend |
| `Backend/` | Vapor REST API (PostgreSQL, Redis) |
| `docs/` | Architecture diagrams and decision records |

## License

[MIT](LICENSE)
