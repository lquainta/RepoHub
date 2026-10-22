# Configuration and secrets

## Rules

1. **No secrets in the repository.** Not in code, tests, fixtures, logs, or commit history. Secret scanning and Gitleaks enforce this (#48).
2. **All backend configuration comes from environment variables**, read through `EnvironmentReader` in `Backend/Sources/App/Configuration/`. Never call `Environment.get` directly from feature code.
3. **Every variable is documented in [`.env.sample`](../.env.sample).** The `Env sample` CI check fails if the backend reads a variable that isn't listed there.
4. **Fail fast.** `AppConfig` is loaded in `configure(_:)` before anything else. A missing or malformed variable throws a `ConfigurationError` that names the variable, and the process exits before serving traffic.

## Secret scanning

| Layer | What it does |
| --- | --- |
| GitHub push protection | Rejects pushes containing known token formats before they reach GitHub |
| GitHub secret scanning | Alerts on secrets anywhere in the repository |
| Gitleaks (`Secret scan` workflow) | Scans full git history on every PR, every push to `main`, and weekly. Required check |
| `make secrets-scan` | Same scan locally, on history and the working tree, including untracked files |

If a secret is ever committed, **rotate it immediately**. Removing it from history doesn't make it safe again.

## Local development

```sh
cp .env.sample .env      # git-ignored
make run-backend
```

Vapor loads `.env` and then `.env.<environment>` (for example `.env.testing`) from the working directory. Both patterns are git-ignored; only `.env.sample` is committed.

## Environments

The backend runs in one of three [Vapor environments](https://docs.vapor.codes/basics/environment/). Each has its **own database**, so tests and development never touch production data.

| Environment | Selected by | Database | Where it runs |
| --- | --- | --- | --- |
| `development` | default for `swift run App serve` / `make run-backend` | `repohub_dev` | docker compose (`make up`) or the DevContainer |
| `testing` | `swift test` (`Application.make(.testing)`) | `repohub_test`, from **`TEST_DATABASE_URL`** | CI service container, DevContainer, compose, or any local Postgres |
| `production` | `--env production` (the Docker image's default command) | managed Postgres on Fly.io (#42) | Fly.io |

- **Configuration:** each environment reads `DATABASE_URL`. Vapor also loads `.env.<environment>` (for example `.env.testing`) after `.env`, so environment-specific values can live there (git-ignored).
- **Tests can't touch other databases.** Integration tests use only `TEST_DATABASE_URL`, never `DATABASE_URL`. They **refuse to run unless the database name ends in `_test`**, because each test migrates a fresh schema and drops every table afterwards. Without `TEST_DATABASE_URL`, they're skipped.
- **Each test database is reset per run:** every integration test reverts leftovers, migrates an empty schema, and reverts it afterwards.
- **Production TLS:** in production, database TLS is required unless the URL sets `sslmode` (see `.env.sample`).
- **Sample data:** `make seed` (`swift run App seed`) fills a development database with two users, five repositories (GitHub and non-GitHub), three groups, 30 days of snapshots, and webhook events. It's idempotent, refuses `--env production`, and runs when the DevContainer is created. Seeded GitHub tokens are placeholder bytes, not real tokens.
- **Test databases already exist** in the DevContainer and docker compose: `repohub_test` is created by `.devcontainer/postgres-init/`, next to `repohub_dev`.

## Adding a variable

In the same PR:

1. Read it in `AppConfig` with `reader.required("NAME")`, `reader.optional("NAME")`, or `reader.integer("NAME", default:)`.
2. Add it to `.env.sample` with a comment and a placeholder value, never a real one.
3. Add a test in `ConfigurationTests` if it has parsing or validation logic.
4. If it's needed in CI or production, add it to the matching secret store below.

## Where real values live

| Environment | Store |
| --- | --- |
| Local | `.env` (git-ignored) |
| CI | GitHub Actions secrets, scoped to the job that needs them |
| Production | Hosting provider's secret store (#42), and the GitHub `production` environment for deploy credentials (#43) |

## macOS app

- The app ships **no secrets**. GitHub sign-in uses the OAuth device flow (#75), which doesn't need a client secret on the device.
- The GitHub token never reaches the app: the backend completes the device flow and keeps it. The app gets a session (a 15-minute access token and a single-use refresh token).
- The refresh token is stored only in the **Keychain** (one generic password item, service `com.lquainta.RepoHub`, readable only while the Mac is unlocked), never in `UserDefaults`, files, or logs. Access tokens stay in memory. Signing out revokes the session on the server and deletes the item.
- The backend defaults to production (`https://repohub-backend.fly.dev`). Set `REPOHUB_BACKEND_URL` in the scheme's environment to use another one, for example `http://localhost:8080` with `make run-backend`.
- UI tests (`REPOHUB_UI_TEST_IN_MEMORY_STORE=1`) keep credentials in memory and never touch the Keychain.

## Error tracking (Sentry)

| Where | Setting | Effect |
| --- | --- | --- |
| Backend | `SENTRY_DSN` (Fly secret) | Unhandled errors and 5xx responses are sent to the `repohub-backend` project with the request's method, path (never the query string), `request_id`, release (`BUILD_COMMIT`), and stack. Unset: only logged. |
| Backend | `DEBUG_TOKEN` | Enables `GET /debug/error` with `X-Debug-Token`, which fails on purpose to check reporting. Unset in production except while checking. |
| App | `SENTRY_DSN` build setting → `SentryDSN` in Info.plist | Release builds pass the `repohub-macos` DSN (`SENTRY_DSN_APP` repository variable). Empty in development builds, so nothing is sent. |
| App | Settings → General → **Send crash reports** | Off by default; reporting starts only after the user opts in, at the next launch. `REPOHUB_FORCE_CRASH=1` crashes at launch to check it. |

DSNs aren't secrets (Sentry designs them to ship in apps), but neither project collects personal data: `sendDefaultPii` is off and breadcrumbs, which could contain paths, are dropped. One-time setup: `scripts/setup-monitoring.sh <alert-email>`.

## Alerts

| What | How | Throttle |
| --- | --- | --- |
| Backend unhandled error or 5xx | `EmailAlerter` emails `ALERT_EMAIL_TO` through Resend (`EMAIL_API_KEY`), with the error, request, and `request_id` | One email per error (type, method, path) per 15 minutes, at most 10 an hour, tracked in Redis (sent anyway if Redis is down) |
| App crash | Sentry workflows on `repohub-macos`: "Email on new or regressed crashes", and Sentry's default high-priority workflow, which also fires when an issue escalates (spikes) | Sentry, at most every 30 minutes per issue |
| Backend down | UptimeRobot checks `/ready` every 5 minutes and emails when it doesn't report `"ready"` (database or Redis down, or no response) | UptimeRobot |

Resend has no verified domain, so it can only email the account owner, which is the maintainer.
