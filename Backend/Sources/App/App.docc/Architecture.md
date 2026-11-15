# Architecture

How a request flows through the backend, and where state lives.

## Request flow

1. Vapor middleware: request ID and structured logging, error reporting (``ErrorReportingMiddleware``), body limits, rate limits per IP, and webhook signature checks.
2. The generated OpenAPI server decodes the request, and ``AuthenticationMiddleware`` checks the bearer token for every operation the spec doesn't mark `security: []`. The user is available to handlers as ``RequestContext/user``.
3. ``APIHandler`` calls a service: ``AuthService``, ``RepositoryStatusService``, ``WorkspaceSync``, ``ActivityService``, or ``EventHub``.

## State

| Where | What | Notes |
| --- | --- | --- |
| PostgreSQL | Users (GitHub token encrypted with ``TokenCipher``), devices (refresh token hashes), workspaces, repositories, groups, snapshots, webhook deliveries | Schema from ``Migrations``, every one reversible |
| Redis | GitHub responses per user (``GitHubCache``), rate-limit counters, alert throttles | Disposable: everything rebuilds from GitHub |
| Memory | Open event streams (``EventHub``) | One machine; more would need Redis pub/sub |

## GitHub

The backend holds each user's GitHub token, and the app never sees it. ``GitHubCache`` serves repeated requests from Redis within short TTLs and revalidates stale entries with ETags, which don't count against GitHub's rate limit. Webhooks (verified by ``WebhookSignature``) clear a repository's cache and notify the users who had it cached through ``EventHub``.

## Diagrams

Component, deployment, and sequence diagrams are in `docs/architecture/` in the repository.
