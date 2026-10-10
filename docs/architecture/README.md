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

Diagrams (C4 context, containers, sequences) are in progress in #54.

## Decisions

Why it's built this way is recorded in the [Architecture Decision Records](../adr/README.md):

- Structure: [monorepo](../adr/0002-use-a-monorepo.md), [SwiftUI + Vapor](../adr/0003-use-swiftui-and-vapor.md)
- Git access: [git CLI instead of libgit2](../adr/0004-run-the-git-cli.md)
- Data: [PostgreSQL](../adr/0005-use-postgresql.md), [Redis cache](../adr/0006-cache-github-responses-in-redis.md)
- API: [spec-first OpenAPI](../adr/0008-design-the-api-spec-first.md)
- Operations: [Fly.io hosting](../adr/0007-host-on-fly-io.md), [ad-hoc signed distribution](../adr/0009-distribute-ad-hoc-signed-builds.md)
