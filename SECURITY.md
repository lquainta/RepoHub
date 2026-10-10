# Security policy

## Reporting a vulnerability

Please **don't open a public issue** for security problems.

Report privately through GitHub: **Security → [Report a vulnerability](https://github.com/lquainta/RepoHub/security/advisories/new)**. Include what you found, how to reproduce it, and its impact.

- You'll get an acknowledgement within **3 days** and an assessment within **7 days**.
- Fixes for confirmed issues are prioritized by severity. You'll be credited in the advisory unless you prefer otherwise.
- Please give us a reasonable time to fix the issue before disclosing it.

## Supported versions

RepoHub is a student project under active development. Only the latest release and `main` receive fixes.

## How RepoHub protects your data

**The macOS app**
- Repository status is read locally by running `git`; nothing about your local repositories is sent anywhere.
- The app never sees your GitHub token. It stores only RepoHub's session refresh token, in the **Keychain**.

**The backend**
- **Sign-in:** GitHub's OAuth device flow, run by the backend. No client secret is needed or stored.
- **GitHub tokens** are encrypted at rest with **AES-256-GCM** (`TOKEN_ENCRYPTION_KEY`). Signing out of your last device erases the token.
- **Sessions:**
  - **Access tokens:** HS256 JWTs that expire after 15 minutes. Each request also checks that its device is still signed in.
  - **Refresh tokens:** 256 random bits, stored only as **SHA-256 hashes**, and **rotated on every use**, so a stolen, already-used token doesn't work.
- **Authorization:** every API operation requires a token unless the OpenAPI spec explicitly marks it public (a test keeps the list in sync).
- **Webhooks:** GitHub deliveries are verified with **HMAC-SHA256** (`X-Hub-Signature-256`) over the raw body, compared in constant time. Redelivered events are ignored.
- **Abuse limits:**
  - **rate limits:** per IP (stricter for sign-in) and per user, answered with `429` and `Retry-After`
  - **request size limits:** 64 KB, or 1 MB for webhooks
  - **input validation**
- **Transport and secrets:**
  - TLS is required to the database in production.
  - Secrets come only from the environment or the hosting provider's secret store, never the repository (see [docs/configuration.md](docs/configuration.md)).
  - Gitleaks and GitHub secret scanning run on every push.
- **Dependencies:** Dependabot keeps them up to date, and CodeQL scans the code.
