# DevContainer

A containerized development environment for the **backend** and **RepoHubCore**. It works with VS Code Dev Containers, GitHub Codespaces, or the `devcontainer` CLI.

The macOS app needs Xcode, so it's built on the host with `make build-app`.

## What's inside

| Service | Image | Purpose | Forwarded port |
| --- | --- | --- | --- |
| `dev` | `swift:6.4-noble` plus SwiftLint 0.65.0 and Gitleaks 8.30.1 (`Dockerfile`) | Workspace, build, and test | 8080 (API) |
| `postgres` | `postgres:18.6-alpine` | `repohub_dev` and `repohub_test` databases | 5432 |
| `redis` | `redis:8.10-alpine` | Cache | 6379 |

The workspace is mounted at `/workspaces/RepoHub`. `Backend/.build` and `Packages/RepoHubCore/.build` are separate named volumes, so Linux build output never mixes with the host's macOS builds.

`DATABASE_URL`, `REDIS_URL`, `LOG_LEVEL`, and `BUILD_COMMIT` are preset in `docker-compose.yml`. The credentials are **local-only defaults** for throwaway containers.

## Usage

**VS Code**: install the *Dev Containers* extension, open the repo, and choose **Reopen in Container**.

**CLI**:

```sh
npx @devcontainers/cli up --workspace-folder .
npx @devcontainers/cli exec --workspace-folder . make test-backend
npx @devcontainers/cli exec --workspace-folder . make run-backend   # http://localhost:8080/health
```

`post-create.sh` resolves packages and builds the backend on first start. Migrations and seed data will be added there (#31, #33).

## CI

The `DevContainer` job in `ci.yml` builds this environment with `devcontainers/ci` and runs the core and backend tests, lint, format, and env checks inside it, then checks that Postgres and Redis are reachable. It's a required check, so the DevContainer can't silently break.
