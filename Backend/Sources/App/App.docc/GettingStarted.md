# Getting Started

Run the backend locally, call it, and test it.

## Run it

With Docker (or OrbStack), from the repository root:

```sh
make up                      # PostgreSQL, Redis, migrations, and the API on :8080
curl localhost:8080/health
open http://localhost:8080/docs
```

Or run it from source against those services: `make run-backend`. Configuration comes from the environment; every variable is in `.env.sample`, and ``AppConfig`` refuses to start with a missing or malformed one in production.

## Call it

Most operations need a session. Sign in through the device flow (the app does this for you):

```sh
curl -X POST localhost:8080/auth/device                  # → userCode, verificationURI, deviceCode
# approve the code on GitHub, then:
curl -X POST localhost:8080/auth/device/token -H 'Content-Type: application/json' \
  -d '{"deviceCode":"…","deviceName":"My Mac"}'          # → accessToken, refreshToken
curl localhost:8080/me -H "Authorization: Bearer <accessToken>"
```

Development needs a GitHub OAuth app's `GITHUB_CLIENT_ID`; without one, sign-in answers `503` and everything else still works.

## Test it

```sh
make test-backend            # unit tests; integration tests skip without databases
make up && make test-integration   # also against real PostgreSQL and Redis
```

Integration tests only run against a database whose name ends in `_test`, because they drop every table.

## Change the API

Edit `openapi/openapi.yaml` first, then `make lint-openapi`, then build: the new operation is a compile error in ``APIHandler`` until it's implemented.
