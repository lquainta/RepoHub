# 0001. Record architecture decisions

- **Status:** Accepted
- **Date:** 2026-10-08
- **Issue:** #60

## Context and problem statement

RepoHub is built by one developer, with AI assistance, over a semester. Decisions about structure, tools, and services are made quickly and are hard to reconstruct later. Reviewers (and future me) need to know *why* the code looks the way it does, not only *what* it does.

## Decision drivers

- Decisions must be reviewable in pull requests, like code.
- Recording a decision must take minutes, not hours.
- Superseded decisions must stay visible, with a pointer to what replaced them.

## Considered options

1. Architecture Decision Records in [MADR](https://adr.github.io/madr/) format, in `docs/adr/`
2. A single "design decisions" section in the README
3. GitHub Discussions or issue comments

## Decision outcome

Chosen option: **MADR files in `docs/adr/`**, numbered sequentially and never renumbered.

- New ADRs start from [`template.md`](template.md) and are added in the PR that implements the decision.
- An ADR is never edited to change its decision. A new ADR supersedes it, and the old one's status links to the replacement.
- [`README.md`](README.md) indexes every ADR, and the architecture docs link to them.

### Consequences

- Good: decisions are versioned, reviewed, and searchable next to the code.
- Good: the PR template's documentation checklist already asks for ADR updates.
- Bad: one more file per significant decision.

## Pros and cons of the options

### README section

- Good: one place to read.
- Bad: grows without structure; no history of reversed decisions.

### Discussions or issues

- Good: easy to write.
- Bad: not versioned with the code; scattered across threads.
