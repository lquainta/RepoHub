# Configuration and secrets

## Rules

1. **No secrets in the repository.** Not in code, tests, fixtures, logs, or commit history. Secret scanning and Gitleaks enforce this (#48).
2. **All backend configuration comes from environment variables**, read through `EnvironmentReader` in `Backend/Sources/App/Configuration/`. Never call `Environment.get` directly from feature code.
3. **Every variable is documented in [`.env.sample`](../.env.sample).** The `Env sample` CI check fails if the backend reads a variable that isn't listed there.
4. **Fail fast.** `AppConfig` is loaded in `configure(_:)` before anything else. A missing or malformed variable throws a `ConfigurationError` that names the variable, and the process exits before serving traffic.

## Local development

```sh
cp .env.sample .env      # git-ignored
make run-backend
```

Vapor loads `.env` and then `.env.<environment>` (for example `.env.testing`) from the working directory. Both patterns are git-ignored; only `.env.sample` is committed.

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
- User tokens are stored only in the **Keychain**, never in `UserDefaults`, files, or logs.
- Non-secret build settings (like the backend base URL) come from build configuration, not hard-coded literals.
