# 0010. Run single-node Postgres and pay-as-you-go Redis on Fly.io

- **Status:** Accepted
- **Date:** 2026-10-10
- **Issue:** #42

## Context and problem statement

[ADR 0007](0007-host-on-fly-io.md) chose Fly.io and left the database offering open. The backend needs a production PostgreSQL database and a Redis cache. The project is one developer's course project, paid for personally, with little traffic.

## Decision drivers

- Monthly cost: the owner set a budget of about $6/month.
- Recoverable data: production must be backed up on a schedule (rubric, #34).
- Private networking between the API and its data stores, and no credentials in the repository.
- Little operational work.

## Considered options

1. Fly Postgres single node (shared-cpu-1x, 256 MB, 1 GB volume, about $2/month) plus Upstash Redis pay-as-you-go
2. Fly Managed Postgres, Basic plan ($38/month plus storage) plus Upstash Redis
3. An external free tier (Neon or Supabase) plus Upstash Redis

## Decision outcome

Chosen option: **Fly Postgres single node and Upstash Redis pay-as-you-go**, both in `dfw` (Dallas, the closest region with Postgres support to the owner).

| Resource | Spec | Cost |
| --- | --- | --- |
| `repohub-backend` | 1 × shared-cpu-1x, 512 MB, always on | about $3.69/month |
| `repohub-db` | Fly Postgres (flex), 1 × shared-cpu-1x, 256 MB, 1 GB volume | about $2.15/month |
| `repohub-redis` | Upstash Redis, pay-as-you-go, eviction on, no replicas | $0.20 per 100K commands (cents/month) |

- **Network:** the API reaches Postgres over Fly's private WireGuard network (`flycast`). The attached `DATABASE_URL` therefore uses `sslmode=disable` explicitly, which our TLS policy allows for private networks (see `.env.sample`).
- **Credentials:** `fly postgres attach` created a dedicated database (`repohub`) and user for the app. Everything else is set with `fly secrets`.

### Consequences

- Good: fits the budget; the same platform for everything; private networking; `fly deploy` runs migrations as a release command before traffic moves.
- Bad: Fly doesn't operate unmanaged Postgres for us. There's no automatic failover, and upgrades are ours to do. A volume failure loses data newer than the last backup.
- Mitigation: nightly encrypted `pg_dump` to object storage, plus a tested restore procedure (#34). Fly also keeps daily volume snapshots, a second layer. Readiness checks (#53) and the uptime monitor surface outages quickly.
- Neutral: moving to Managed Postgres later is a dump-and-restore plus a new `DATABASE_URL`, with no code change.

## Pros and cons of the options

### Managed Postgres

- Good: backups, failover, and upgrades handled by Fly.
- Bad: about 7× the whole budget for one service.

### External free tier

- Good: free.
- Bad: another account, connections over the public internet, free-tier limits (pausing, connection caps), and data outside Fly's private network.
