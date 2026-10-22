# RepoHub API specification

[`openapi.yaml`](openapi.yaml) is the **single source of truth** for the backend's HTTP API ([ADR 0008](../docs/adr/0008-design-the-api-spec-first.md)).

| Generated from it | Where | How |
| --- | --- | --- |
| Server types and route registration | `Backend/Sources/RepoHubAPI` (`openapi.yaml` is a symlink) | `swift-openapi-generator` build plugin; implemented by `APIHandler` |
| The app's client | `Packages/RepoHubAPIClient` (symlink) | same plugin; used by the macOS app |
| API reference | `GET /docs` (Redoc) and `GET /openapi.yaml` | served by the backend |

Nothing generated is committed. It's produced on every build, so code that disagrees with the spec doesn't compile.

## Changing the API

1. Edit `openapi.yaml`: add the path, `operationId`, request and response schemas, and `security` (`[]` for public endpoints).
2. `make lint-openapi`. Redocly's strict ruleset ([`redocly.yaml`](redocly.yaml)) runs in CI, and every finding fails the build.
3. Build the backend. The new operation is a compile error in `APIHandler` until it's implemented.
4. The app gets the matching method on `Client` automatically.
5. Open `http://localhost:8080/docs` to check the rendered reference.

Keep changes backward compatible where possible: the app in users' hands may be older than the server.
