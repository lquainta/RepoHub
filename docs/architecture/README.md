# Architecture

RepoHub is a native macOS app with an optional backend. The app works fully offline for local repositories. The backend adds GitHub sign-in, pull request and CI data, and sync across Macs.

## Components

| Component | Path | Runs on | Responsibility |
| --- | --- | --- | --- |
| **App** | `App/` | macOS 15+ | SwiftUI dashboard, detail view, actions, menu bar; SwiftData for local state |
| **RepoHubCore** | `Packages/RepoHubCore/` | macOS and Linux | Git command runner, output parsers, models, repository scanner, stale branch detection |
| **Backend** | `Backend/` | Linux (Docker, Fly.io) | Vapor REST API: authentication, GitHub proxy and cache, sync |
| PostgreSQL | managed | Fly.io | Users, devices, workspaces, groups, snapshots, webhook events ([database design](database.md)) |
| Redis | managed | Fly.io (Upstash) | GitHub response cache |

## Diagrams

All in Mermaid, rendered by GitHub, and named after the types in the code. `make check-diagrams` (in CI) fails if a diagram names a type that no longer exists, so a rename has to update the diagram too.

| Diagram | Shows |
| --- | --- |
| [Components](components.md#components) | The app's models and views, RepoHubCore, and the backend's services, and how they call each other |
| [Deployment](components.md#deployment) | The Mac, GitHub (Actions, API, webhooks), Fly.io (API, PostgreSQL, Redis, Tigris), Sentry, Resend, UptimeRobot |
| [RepoHubCore classes](core.md) | `GitServicing` and `GitService`, the runner, scanner, parsers, and the status and branch models |
| [Scanning and refreshing](sequences.md#scanning-and-refreshing) | Adding a folder, reading statuses (8 at a time), file-change refresh |
| [GitHub sign-in](sequences.md#github-sign-in-oauth-device-flow) | The device flow through the backend; the token never reaches the app |
| [Cached GitHub request and live updates](sequences.md#a-cached-github-request-and-live-updates) | Redis TTLs, ETag revalidation, pagination, webhook, `/events` |
| [Continuous deployment](sequences.md#continuous-deployment) | CI, release PR, deploy with migrations, smoke test, rollback |
| [Database](database.md) | The ERD and every table |

## Decisions

Why it's built this way is recorded in the [Architecture Decision Records](../adr/README.md):

- Structure: [monorepo](../adr/0002-use-a-monorepo.md), [SwiftUI + Vapor](../adr/0003-use-swiftui-and-vapor.md)
- Git access: [git CLI instead of libgit2](../adr/0004-run-the-git-cli.md)
- Data: [PostgreSQL](../adr/0005-use-postgresql.md), [Redis cache](../adr/0006-cache-github-responses-in-redis.md)
- API: [spec-first OpenAPI](../adr/0008-design-the-api-spec-first.md). The spec and workflow are in [`openapi/`](../../openapi/README.md), and the running backend serves its reference at `/docs`.
- Operations: [Fly.io hosting](../adr/0007-host-on-fly-io.md), [ad-hoc signed distribution](../adr/0009-distribute-ad-hoc-signed-builds.md)
