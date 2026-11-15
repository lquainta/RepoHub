# ``App``

The RepoHub backend: GitHub sign-in, pull request and CI data, live updates, and sync between Macs.

## Overview

A Vapor server, designed spec-first: `openapi/openapi.yaml` generates the route registration and request/response types, and ``APIHandler`` implements them. The app's client is generated from the same file, so the two can't disagree.

It stores users, devices, workspaces, groups, and activity in PostgreSQL, caches GitHub responses in Redis, and runs on Fly.io. Local repository status never reaches it.

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:Architecture>
- ``configure(_:reader:)``
- ``AppConfig``

### API

- ``APIHandler``
- ``AuthenticationMiddleware``
- ``RequestContext``

### Sign-in and sessions

- ``AuthService``
- ``GitHubOAuth``
- ``SessionTokens``
- ``TokenCipher``

### GitHub data

- ``GitHubAPI``
- ``VaporGitHubAPI``
- ``GitHubCache``
- ``GitHubResource``
- ``RepositoryStatusService``

### Live updates

- ``EventHub``
- ``RepositoryChange``
- ``WebhookSignature``

### Sync and activity

- ``WorkspaceSync``
- ``ActivityService``

### Data

- ``User``
- ``Device``
- ``Workspace``
- ``TrackedRepo``
- ``RepoGroup``
- ``RepoSnapshot``
- ``WebhookEvent``
- ``Migrations``

### Operations

- ``ReadinessChecker``
- ``ErrorReportingMiddleware``
- ``SentryReporter``
- ``EmailAlerter``
- ``RateLimiter``
