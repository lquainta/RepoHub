# 0002. Use a monorepo for the app, shared core, and backend

- **Status:** Accepted
- **Date:** 2026-10-08
- **Issue:** #60, #11

## Context and problem statement

RepoHub has three parts: a macOS app, a backend API, and git parsing and models that both need. They change together. For example, a new status field touches the parser, the app's dashboard, and the API.

## Decision drivers

- One pull request should be able to change every affected part, with one CI run proving they still fit together.
- Shared code must not be copied between projects.
- Issue → branch → PR traceability is a course requirement and should cover all components.

## Considered options

1. One repository: `App/`, `Packages/RepoHubCore/`, `Backend/`
2. Separate repositories, with the core published as a versioned Swift package
3. App and core together, with the backend in a separate repository

## Decision outcome

Chosen option: **one repository**, with the core as a local Swift package (`Packages/RepoHubCore`) that the app (via XcodeGen) and the backend (via `Package.swift`) both depend on by path.

### Consequences

- Good: atomic cross-component changes and a single CI pipeline; no version skew between app and backend models.
- Good: one issue tracker, board, and history.
- Bad: CI builds everything on every PR. Mitigated by caching and parallel jobs; the slow backend CodeQL analysis runs only on `main` and weekly.
- Neutral: the core must stay platform-neutral (macOS and Linux), since the backend runs on Linux. CI tests it on both.

## Pros and cons of the options

### Separate repositories

- Good: independent release cycles.
- Bad: every model change needs a core release, then two dependency bumps; overkill for one developer.

### Backend separate

- Good: smaller app repository.
- Bad: shared models drift or get duplicated.
