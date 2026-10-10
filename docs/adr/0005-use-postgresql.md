# 0005. Use PostgreSQL with Fluent for backend persistence

- **Status:** Accepted
- **Date:** 2026-10-09
- **Issue:** #60, #29, #30

## Context and problem statement

The backend stores users, devices and sessions, synced workspaces and repository groups, tracked repositories, activity snapshots, and received webhook events (schema designed in #29). The data is relational: users own workspaces, which own groups and repositories in a many-to-many relationship.

## Decision drivers

- Relational integrity (foreign keys, unique constraints, cascades) enforced by the database, not only by code.
- Version-controlled, reversible migrations (#31).
- Managed hosting with automated backups (#34) on the chosen provider ([0007](0007-host-on-fly-io.md)).
- Good Swift support.

## Considered options

1. PostgreSQL with Fluent and `fluent-postgres-driver`
2. SQLite with Fluent
3. A document store (MongoDB)

## Decision outcome

Chosen option: **PostgreSQL**, accessed through Fluent models and migrations, configured only from `DATABASE_URL`.

### Consequences

- Good: real constraints and transactions; `jsonb` for settings and webhook payloads; `timestamptz` for sync timestamps.
- Good: first-class in Vapor and on managed hosts; `pg_dump` for backups.
- Bad: needs a server locally. The DevContainer and docker-compose provide one.
- Neutral: separate databases per environment (`repohub_dev`, `repohub_test`, production) (#32).

## Pros and cons of the options

### SQLite

- Good: zero setup.
- Bad: single-writer; awkward on ephemeral container filesystems; no managed backups.

### MongoDB

- Good: flexible documents.
- Bad: the data is relational; integrity would move into application code.
