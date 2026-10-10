# 0008. Design the API spec-first with OpenAPI

- **Status:** Accepted
- **Date:** 2026-10-09
- **Issue:** #60, #55

## Context and problem statement

The app and the backend talk over HTTP. Hand-written clients and servers drift: a renamed field breaks the app at runtime, and the API docs go stale.

## Decision drivers

- A single source of truth for endpoints, schemas, authentication, and errors.
- Compile-time errors when the app or backend disagrees with the contract.
- Human-readable docs that can't drift from the code.

## Considered options

1. An OpenAPI document (`openapi.yaml`) first; generate server stubs and the client with `swift-openapi-generator`
2. Code first: write Vapor routes, then generate a spec from them
3. No spec; share Swift model types through `RepoHubCore`

## Decision outcome

Chosen option: **spec-first OpenAPI**.

- The spec generates Vapor server stubs (through the `swift-openapi-vapor` transport) and the app's client.
- CI lints the spec.
- Rendered docs are served at `/docs`.

### Consequences

- Good: contract changes are reviewed as a diff to the spec; generated code fails to compile if a handler or caller is out of date.
- Good: any client, such as `curl`, Postman, or a future web client, can rely on the spec.
- Bad: generated types are more verbose than hand-written ones; a thin mapping layer converts them to domain models.

## Pros and cons of the options

### Code-first

- Good: fast to start.
- Bad: Vapor has no reliable spec generation; docs would be hand-maintained.

### Shared Swift types only

- Good: simplest.
- Bad: no published contract; nothing checks status codes, authentication, or errors.
