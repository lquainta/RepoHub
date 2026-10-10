# Architecture Decision Records

Significant decisions, why they were made, and what they cost. Format: [MADR](https://adr.github.io/madr/). See [0001](0001-record-architecture-decisions.md) for how this works.

| ADR | Decision | Status |
| --- | --- | --- |
| [0001](0001-record-architecture-decisions.md) | Record architecture decisions | Accepted |
| [0002](0002-use-a-monorepo.md) | Use a monorepo for the app, shared core, and backend | Accepted |
| [0003](0003-use-swiftui-and-vapor.md) | Use SwiftUI for the app and Vapor for the backend | Accepted |
| [0004](0004-run-the-git-cli.md) | Read repositories by running the git CLI, not libgit2 | Accepted |
| [0005](0005-use-postgresql.md) | Use PostgreSQL with Fluent for backend persistence | Accepted |
| [0006](0006-cache-github-responses-in-redis.md) | Cache GitHub API responses in Redis | Accepted |
| [0007](0007-host-on-fly-io.md) | Host the backend on Fly.io | Accepted |
| [0008](0008-design-the-api-spec-first.md) | Design the API spec-first with OpenAPI | Accepted |
| [0009](0009-distribute-ad-hoc-signed-builds.md) | Distribute the app as an ad-hoc signed DMG | Accepted |

## Adding an ADR

1. Copy [`template.md`](template.md) to `NNNN-short-title.md`, using the next number.
2. Fill it in and add it to the table above, in the PR that implements the decision.
3. To reverse a decision, write a new ADR and set the old one's status to "Superseded by NNNN". Never rewrite an accepted ADR's decision.
