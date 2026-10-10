# Deployment

## Container image

The backend ships as a Docker image built from [`Backend/Dockerfile`](../Backend/Dockerfile). The build context is the repository root, because the backend depends on `Packages/RepoHubCore` by path.

```sh
make docker-build                  # repohub-backend:dev, tagged with the current commit
cp .env.sample .env                # set DATABASE_URL (host.docker.internal for a DB on the host)
docker run --rm --env-file .env repohub-backend:dev migrate --yes
make docker-run                    # http://localhost:8080/health
```

### Image layout

| Stage | Base | Contents |
| --- | --- | --- |
| `build` | `swift:6.4-noble` | Resolves dependencies in their own layer (cached until `Package.*` changes), then `swift build -c release`, linking jemalloc |
| runtime | `swift:6.4-noble-slim` | The Swift runtime libraries only, plus `ca-certificates`, `tzdata`, `libjemalloc2`, and `curl` for the health check |

- **Non-root:** runs as the unprivileged system user `vapor`, which owns only `/app`.
- **Health check:** `HEALTHCHECK` calls `GET /health` every 30 seconds, so Docker and the hosting platform can restart an unhealthy container.
- **Build commit:** `--build-arg BUILD_COMMIT=<sha>` is baked in as an environment variable and reported by `/health`.
- **Crash logs:** Swift's backtracer is enabled, so crashes print symbolicated backtraces.
- **Default command:** `serve --env production --hostname 0.0.0.0 --port 8080`. Run `migrate --yes` with the same image before starting a new version (#43).
- **Context:** `.dockerignore` sends only the two packages' manifests, sources, and tests (SwiftPM requires every declared target to exist).

### Size

Measured on 2026-10-09 (arm64; amd64 is similar):

| | Size |
| --- | --- |
| Runtime base (`swift:6.4-noble-slim`) | 439 MB |
| RepoHub layers (app binary 115 MB + system packages) | ~170 MB |
| **Total, uncompressed** | **609 MB** |
| **Compressed (what a registry stores and a host pulls)** | **135 MB** |

`--static-swift-stdlib` with a plain `ubuntu:noble` base would be smaller, but it fails to link Foundation with Swift 6.4. Revisit this when the toolchain fixes it.

### CI

The `Docker image` job in [`ci.yml`](../.github/workflows/ci.yml) builds the image on every PR and push to `main`, using the GitHub Actions layer cache. It then smoke-tests it:
- `/health` returns `ok` with the right commit
- the process isn't root
- Docker reports the container `healthy`
