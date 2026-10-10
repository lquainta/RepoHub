# 0007. Host the backend on Fly.io

- **Status:** Accepted
- **Date:** 2026-10-09
- **Issue:** #60, #42

## Context and problem statement

The backend needs a public HTTPS endpoint, a managed PostgreSQL database, Redis, a secret store, and deploys from CI on a student budget.

## Decision drivers

- Deploys a Docker image (#39) from GitHub Actions with a scoped token (#43).
- Managed Postgres with automated backups, plus Redis.
- Secrets in the provider's store, never in the repository.
- Low or no cost at this scale; health checks and rollbacks.

## Considered options

1. Fly.io: Fly Machines, Postgres on Fly, Upstash Redis through Fly
2. Render: web service, Render Postgres, Render Key Value
3. A VPS (DigitalOcean or Hetzner) with docker-compose

## Decision outcome

Chosen option: **Fly.io**, as the app `repohub-backend` at <https://repohub-backend.fly.dev>.

- Deployed with `flyctl deploy` from the CD workflow.
- Configured with `fly secrets`.
- Health checks hit `/health` (liveness) and `/ready` (database and Redis).

### Consequences

- Good: Docker-native; the CLI works well in CI; automatic TLS; machine health checks and release rollback.
- Good: Upstash Redis is provisioned through Fly, so there's no separate account.
- Bad: the free allowance is small, and a card is required on the account.
- Neutral: the exact Postgres offering (Managed Postgres or a self-managed Postgres app) and its backup setup are chosen in #42 and #34 and recorded there.

## Pros and cons of the options

### Render

- Good: simple dashboard; free web tier.
- Bad: free instances sleep (slow first request); free databases expire.

### VPS

- Good: cheap and flexible.
- Bad: we would operate TLS, backups, OS updates, and monitoring ourselves.
