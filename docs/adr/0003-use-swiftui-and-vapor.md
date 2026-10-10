# 0003. Use SwiftUI for the app and Vapor for the backend

- **Status:** Accepted
- **Date:** 2026-10-08
- **Issue:** #60

## Context and problem statement

RepoHub needs a native macOS dashboard and a small web API, which handles GitHub sign-in, caches GitHub data, and syncs groups across Macs. We have to pick a UI framework and a server framework.

## Decision drivers

- Native macOS look and behavior: tables, menus, the menu bar, keyboard shortcuts, and accessibility.
- One language across the whole stack, so models and git parsing are shared (see [0002](0002-use-a-monorepo.md)).
- A mature server framework with PostgreSQL, Redis, and testing support.
- Learning value for the course: modern Swift concurrency end to end.

## Considered options

1. SwiftUI (with AppKit where needed) + Vapor 4
2. SwiftUI + a Node.js (Express or Fastify) backend
3. Electron or Tauri + any backend
4. SwiftUI + Hummingbird

## Decision outcome

Chosen option: **SwiftUI + Vapor 4**.

### Consequences

- Good: shared `RepoHubCore` types in both app and backend, with strict Swift 6 concurrency checking everywhere.
- Good: Vapor has first-party Fluent (PostgreSQL), Redis, JWT, and testing packages.
- Bad: Swift on the server has a smaller ecosystem and slower builds than Node. Mitigated by Docker layer caching.
- Bad: some macOS features (FSEvents, the open panel, login items) need AppKit or C APIs behind small wrappers.

## Pros and cons of the options

### Node.js backend

- Good: huge ecosystem, fast iteration.
- Bad: duplicated models in TypeScript; two toolchains.

### Electron or Tauri

- Good: cross-platform.
- Bad: not native; heavy for a menu bar utility; doesn't meet the "native macOS" goal.

### Hummingbird

- Good: lightweight, modern.
- Bad: smaller ecosystem for database and auth than Vapor.
