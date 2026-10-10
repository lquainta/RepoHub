# 0006. Cache GitHub API responses in Redis

- **Status:** Accepted
- **Date:** 2026-10-09
- **Issue:** #60, #35

## Context and problem statement

PR and CI badges (#76) need GitHub data for every tracked repository, refreshed often. GitHub allows 5,000 REST requests per hour per user token. Asking GitHub on every app refresh would hit that limit with a few dozen repositories and would also be slow.

## Decision drivers

- Stay well within GitHub rate limits.
- Fast responses to the app.
- Webhooks (#77) must be able to invalidate stale entries immediately.
- The cache can be lost without losing data.

## Considered options

1. Redis, cache-aside, with per-resource TTLs and stored ETags for conditional requests
2. In-process memory cache in the Vapor app
3. Cache tables in PostgreSQL

## Decision outcome

Chosen option: **Redis cache-aside**.

- Each resource has a TTL: for example, short for check runs and longer for repository metadata.
- ETags are stored with each entry, so refreshes use `If-None-Match`. A `304 Not Modified` doesn't count against the rate limit.
- Webhook events delete the affected keys.
- Hits and misses are logged.

### Consequences

- Good: shared across instances and survives deploys; `EXPIRE` handles TTLs; fast key deletion for invalidation.
- Bad: one more service to run locally (DevContainer and compose include it) and in production.
- Neutral: the backend must keep working if Redis is down. Requests then fall through to GitHub.

## Pros and cons of the options

### In-process cache

- Good: no extra service.
- Bad: lost on every deploy; not shared between machines; webhooks may hit a different instance.

### PostgreSQL tables

- Good: one fewer service.
- Bad: TTL expiry and high-churn writes are a poor fit; adds load to the primary database.
